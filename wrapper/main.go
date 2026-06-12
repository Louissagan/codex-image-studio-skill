package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/textproto"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type stringList []string

func (s *stringList) String() string {
	return strings.Join(*s, ",")
}

func (s *stringList) Set(value string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed != "" {
		*s = append(*s, trimmed)
	}
	return nil
}

type config struct {
	Mode           string
	Prompt         string
	Inputs         []string
	Mask           string
	Size           string
	Quality        string
	Model          string
	BaseURL        string
	APIKey         string
	OutputDir      string
	Metadata       bool
	Raw            bool
	TimeoutSeconds int
	MaxRetries     int
	TaskID         string
}

type metadata struct {
	TaskID          string        `json:"task_id"`
	Mode            string        `json:"mode"`
	Prompt          string        `json:"prompt"`
	InputImages     []string      `json:"input_images"`
	Mask            *string       `json:"mask"`
	Model           string        `json:"model"`
	Size            string        `json:"size"`
	Quality         string        `json:"quality"`
	BaseURL         string        `json:"base_url"`
	OutputImages    []string      `json:"output_images"`
	RawResponsePath string        `json:"raw_response_path"`
	LogPath         string        `json:"log_path"`
	CreatedAt       string        `json:"created_at"`
	Status          string        `json:"status"`
	Error           *metadataErr  `json:"error"`
}

type metadataErr struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type apiImage struct {
	B64JSON       string `json:"b64_json"`
	URL           string `json:"url"`
	RevisedPrompt string `json:"revised_prompt"`
}

type imageResponse struct {
	Created int64      `json:"created"`
	Data    []apiImage `json:"data"`
	Error   any        `json:"error,omitempty"`
}

type requestResult struct {
	ImageBytes []byte
	RawBody    []byte
	StatusCode int
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	cfg := parseFlags()
	if cfg.Mode == "help" {
		flag.Usage()
		return nil
	}
	if err := cfg.applyDefaults(); err != nil {
		return err
	}

	if cfg.TaskID == "" {
		cfg.TaskID = newTaskID()
	}

	paths, err := preparePaths(cfg)
	if err != nil {
		return err
	}

	logf, err := os.OpenFile(paths.LogPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("create log file: %w", err)
	}
	defer logf.Close()
	logLine := func(format string, args ...any) {
		fmt.Fprintf(logf, time.Now().Format(time.RFC3339)+" "+format+"\n", args...)
	}

	meta := metadata{
		TaskID:          cfg.TaskID,
		Mode:            metadataMode(cfg.Mode),
		Prompt:          cfg.Prompt,
		InputImages:     cfg.Inputs,
		Model:           cfg.Model,
		Size:            cfg.Size,
		Quality:         cfg.Quality,
		BaseURL:         cfg.BaseURL,
		OutputImages:    []string{},
		RawResponsePath: paths.RawPath,
		LogPath:         paths.LogPath,
		CreatedAt:       time.Now().UTC().Format(time.RFC3339),
		Status:          "failed",
		Error:           nil,
	}
	if cfg.Mask != "" {
		mask := cfg.Mask
		meta.Mask = &mask
	}

	result, reqErr := requestWithRetries(cfg, logLine)
	if len(result.RawBody) == 0 && reqErr != nil {
		result.RawBody = []byte(fmt.Sprintf(`{"error":{"message":%q}}`, reqErr.Error()))
	}
	if cfg.Raw {
		if err := os.WriteFile(paths.RawPath, result.RawBody, 0o600); err != nil {
			logLine("failed to write raw response: %v", err)
		}
	}

	if reqErr != nil {
		classified := classifyError(result.StatusCode, reqErr, result.RawBody)
		meta.Error = &classified
		writeMetadataIfEnabled(cfg, paths.MetadataPath, meta, logLine)
		return fmt.Errorf("%s", classified.Message)
	}

	if len(result.ImageBytes) == 0 {
		classified := metadataErr{Code: "empty_image", Message: "上游没有返回图片。已保存 raw response，请检查 outputs/raw/。"}
		meta.Error = &classified
		writeMetadataIfEnabled(cfg, paths.MetadataPath, meta, logLine)
		return errors.New(classified.Message)
	}

	if err := os.WriteFile(paths.ImagePath, result.ImageBytes, 0o600); err != nil {
		classified := metadataErr{Code: "write_image_failed", Message: fmt.Sprintf("写入图片失败: %v", err)}
		meta.Error = &classified
		writeMetadataIfEnabled(cfg, paths.MetadataPath, meta, logLine)
		return errors.New(classified.Message)
	}

	meta.Status = "success"
	meta.OutputImages = []string{paths.ImagePath}
	meta.Error = nil
	writeMetadataIfEnabled(cfg, paths.MetadataPath, meta, logLine)

	fmt.Printf("生成图片路径: %s\n", paths.ImagePath)
	fmt.Printf("metadata 路径: %s\n", paths.MetadataPath)
	fmt.Printf("raw response 路径: %s\n", paths.RawPath)
	return nil
}

func parseFlags() config {
	var inputs stringList
	cfg := config{}
	flag.StringVar(&cfg.Mode, "mode", "", "generate | edit")
	flag.StringVar(&cfg.Prompt, "prompt", "", "prompt text or edit instructions")
	flag.Var(&inputs, "input", "source image path for edit mode; may be repeated")
	flag.StringVar(&cfg.Mask, "mask", "", "optional mask image path")
	flag.StringVar(&cfg.Size, "size", "", "image size, default from IMAGE_STUDIO_DEFAULT_SIZE")
	flag.StringVar(&cfg.Quality, "quality", "", "image quality, default from IMAGE_STUDIO_DEFAULT_QUALITY")
	flag.StringVar(&cfg.Model, "model", "", "image model, default from IMAGE_STUDIO_IMAGE_MODEL")
	flag.StringVar(&cfg.BaseURL, "base-url", "", "OpenAI-compatible base URL")
	flag.StringVar(&cfg.APIKey, "api-key", "", "API key")
	flag.StringVar(&cfg.OutputDir, "output-dir", "", "output root directory")
	flag.BoolVar(&cfg.Metadata, "metadata", true, "write metadata JSON")
	flag.BoolVar(&cfg.Raw, "raw", true, "write raw response")
	flag.IntVar(&cfg.TimeoutSeconds, "timeout", 0, "request timeout seconds")
	flag.IntVar(&cfg.MaxRetries, "max-retries", -1, "retry count after first attempt")
	flag.StringVar(&cfg.TaskID, "task-id", "", "optional task id override")
	flag.Parse()
	cfg.Inputs = inputs
	return cfg
}

func (c *config) applyDefaults() error {
	c.Mode = strings.ToLower(strings.TrimSpace(firstNonEmpty(c.Mode, os.Getenv("IMAGE_STUDIO_MODE"))))
	if c.Mode == "" {
		return errors.New("--mode is required: generate or edit")
	}
	if c.Mode != "generate" && c.Mode != "edit" {
		return errors.New("--mode must be generate or edit")
	}
	c.Prompt = strings.TrimSpace(c.Prompt)
	if c.Prompt == "" {
		return errors.New("--prompt is required")
	}
	if c.Mode == "edit" && len(c.Inputs) == 0 {
		return errors.New("输入图片不存在，请检查 --input 或 --input-dir。")
	}

	c.BaseURL = strings.TrimSpace(firstNonEmpty(c.BaseURL, os.Getenv("IMAGE_STUDIO_BASE_URL")))
	if c.BaseURL == "" {
		return errors.New("missing IMAGE_STUDIO_BASE_URL")
	}
	baseURL, err := normalizeBaseURL(c.BaseURL)
	if err != nil {
		return err
	}
	c.BaseURL = baseURL

	c.APIKey = strings.TrimSpace(firstNonEmpty(c.APIKey, os.Getenv("IMAGE_STUDIO_API_KEY")))
	if c.APIKey == "" || c.APIKey == "replace_with_your_api_key" {
		return errors.New("missing IMAGE_STUDIO_API_KEY")
	}
	c.Model = strings.TrimSpace(firstNonEmpty(c.Model, os.Getenv("IMAGE_STUDIO_IMAGE_MODEL"), "gpt-image-1"))
	c.Size = strings.TrimSpace(firstNonEmpty(c.Size, os.Getenv("IMAGE_STUDIO_DEFAULT_SIZE"), "1024x1024"))
	c.Quality = strings.TrimSpace(firstNonEmpty(c.Quality, os.Getenv("IMAGE_STUDIO_DEFAULT_QUALITY"), "high"))
	c.OutputDir = strings.TrimSpace(firstNonEmpty(c.OutputDir, os.Getenv("IMAGE_STUDIO_OUTPUT_DIR"), "./skills/image-studio/outputs"))
	if c.TimeoutSeconds <= 0 {
		c.TimeoutSeconds = intEnv("IMAGE_STUDIO_TIMEOUT_SECONDS", 300)
	}
	if c.MaxRetries < 0 {
		c.MaxRetries = intEnv("IMAGE_STUDIO_MAX_RETRIES", 2)
	}

	for _, input := range c.Inputs {
		if !isSupportedImagePath(input) {
			return fmt.Errorf("unsupported input image type: %s", input)
		}
		if !fileExists(input) {
			return errors.New("输入图片不存在，请检查 --input 或 --input-dir。")
		}
	}
	if c.Mask != "" && !fileExists(c.Mask) {
		return errors.New("输入图片不存在，请检查 --mask。")
	}
	return nil
}

type outputPaths struct {
	ImagePath    string
	MetadataPath string
	RawPath      string
	LogPath      string
}

func preparePaths(cfg config) (outputPaths, error) {
	root, err := filepath.Abs(cfg.OutputDir)
	if err != nil {
		return outputPaths{}, err
	}
	dirs := []string{
		filepath.Join(root, "images"),
		filepath.Join(root, "metadata"),
		filepath.Join(root, "raw"),
		filepath.Join(root, "logs"),
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return outputPaths{}, fmt.Errorf("输出目录不可写，请检查权限: %w", err)
		}
	}
	if err := assertWritable(root); err != nil {
		return outputPaths{}, err
	}

	stem := cfg.TaskID
	if cfg.Mode == "edit" {
		stem += "-edited"
	}
	return outputPaths{
		ImagePath:    filepath.Join(root, "images", stem+".png"),
		MetadataPath: filepath.Join(root, "metadata", stem+".json"),
		RawPath:      filepath.Join(root, "raw", stem+".json"),
		LogPath:      filepath.Join(root, "logs", stem+".log"),
	}, nil
}

func requestWithRetries(cfg config, logLine func(string, ...any)) (requestResult, error) {
	var last requestResult
	var lastErr error
	attempts := cfg.MaxRetries + 1
	for attempt := 1; attempt <= attempts; attempt++ {
		logLine("attempt %d/%d mode=%s model=%s size=%s quality=%s", attempt, attempts, cfg.Mode, cfg.Model, cfg.Size, cfg.Quality)
		ctx, cancel := context.WithTimeout(context.Background(), time.Duration(cfg.TimeoutSeconds)*time.Second)
		result, err := requestOnce(ctx, cfg)
		cancel()
		last = result
		if err == nil {
			return result, nil
		}
		lastErr = err
		if attempt < attempts && isRetryableStatus(result.StatusCode, err) {
			time.Sleep(time.Duration(attempt) * time.Second)
			continue
		}
		break
	}
	return last, lastErr
}

func requestOnce(ctx context.Context, cfg config) (requestResult, error) {
	if cfg.Mode == "edit" {
		return requestEdit(ctx, cfg)
	}
	return requestGenerate(ctx, cfg)
}

func requestGenerate(ctx context.Context, cfg config) (requestResult, error) {
	body := map[string]any{
		"model":   cfg.Model,
		"prompt":  cfg.Prompt,
		"n":       1,
		"size":    cfg.Size,
		"quality": cfg.Quality,
	}
	if supportsResponseFormat(cfg.Model, cfg.Mode) {
		body["response_format"] = "b64_json"
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return requestResult{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, cfg.BaseURL+"/images/generations", bytes.NewReader(encoded))
	if err != nil {
		return requestResult{}, err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")
	return doRequest(req)
}

func requestEdit(ctx context.Context, cfg config) (requestResult, error) {
	buf := &bytes.Buffer{}
	writer := multipart.NewWriter(buf)
	for i, input := range cfg.Inputs {
		field := "image"
		if i > 0 {
			field = "image[]"
		}
		if err := addFilePart(writer, field, input); err != nil {
			return requestResult{}, err
		}
	}
	if cfg.Mask != "" {
		if err := addFilePart(writer, "mask", cfg.Mask); err != nil {
			return requestResult{}, err
		}
	}
	_ = writer.WriteField("model", cfg.Model)
	_ = writer.WriteField("prompt", cfg.Prompt)
	_ = writer.WriteField("n", "1")
	_ = writer.WriteField("size", cfg.Size)
	_ = writer.WriteField("quality", cfg.Quality)
	if supportsResponseFormat(cfg.Model, cfg.Mode) {
		_ = writer.WriteField("response_format", "b64_json")
	}
	if err := writer.Close(); err != nil {
		return requestResult{}, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, cfg.BaseURL+"/images/edits", buf)
	if err != nil {
		return requestResult{}, err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	return doRequest(req)
}

func doRequest(req *http.Request) (requestResult, error) {
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return requestResult{}, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return requestResult{StatusCode: resp.StatusCode}, err
	}
	result := requestResult{RawBody: raw, StatusCode: resp.StatusCode}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return result, fmt.Errorf("upstream returned HTTP %d", resp.StatusCode)
	}

	var parsed imageResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return result, fmt.Errorf("解析 Images API 响应失败: %w", err)
	}
	if len(parsed.Data) == 0 {
		return result, errors.New("no image returned")
	}
	first := parsed.Data[0]
	if first.B64JSON != "" {
		data, err := base64.StdEncoding.DecodeString(first.B64JSON)
		if err != nil {
			return result, fmt.Errorf("decode b64_json: %w", err)
		}
		result.ImageBytes = data
		return result, nil
	}
	if first.URL != "" {
		data, err := downloadImage(req.Context(), first.URL)
		if err != nil {
			return result, err
		}
		result.ImageBytes = data
		return result, nil
	}
	return result, errors.New("empty image")
}

func addFilePart(w *multipart.Writer, fieldName string, path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`, fieldName, filepath.Base(path)))
	header.Set("Content-Type", mimeForPath(path))
	part, err := w.CreatePart(header)
	if err != nil {
		return err
	}
	_, err = io.Copy(part, file)
	return err
}

func downloadImage(ctx context.Context, rawURL string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("download image returned HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

func writeMetadataIfEnabled(cfg config, path string, meta metadata, logLine func(string, ...any)) {
	if !cfg.Metadata {
		return
	}
	data, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		logLine("failed to encode metadata: %v", err)
		return
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		logLine("failed to write metadata: %v", err)
	}
}

func classifyError(status int, err error, raw []byte) metadataErr {
	lower := strings.ToLower(string(raw) + " " + err.Error())
	switch {
	case status == http.StatusUnauthorized || status == http.StatusForbidden:
		return metadataErr{Code: fmt.Sprintf("%d", status), Message: "API Key 无效或权限不足，请检查 IMAGE_STUDIO_API_KEY。"}
	case status == http.StatusNotFound || strings.Contains(lower, "model_not_found"):
		return metadataErr{Code: fmt.Sprintf("%d", status), Message: "模型不存在，请检查 IMAGE_STUDIO_IMAGE_MODEL。"}
	case status == http.StatusGatewayTimeout || status == 524 || strings.Contains(lower, "timeout") || strings.Contains(lower, "deadline exceeded"):
		return metadataErr{Code: "timeout", Message: "图片生成超时，请检查上游服务，或切换为更稳定的 Responses API / SSE 调用方式。"}
	case strings.Contains(lower, "empty image") || strings.Contains(lower, "no image returned"):
		return metadataErr{Code: "empty_image", Message: "上游没有返回图片。已保存 raw response，请检查 outputs/raw/。"}
	case status > 0:
		return metadataErr{Code: fmt.Sprintf("%d", status), Message: err.Error()}
	default:
		return metadataErr{Code: "request_failed", Message: err.Error()}
	}
}

func normalizeBaseURL(raw string) (string, error) {
	cleaned := strings.TrimRight(strings.TrimSpace(raw), "/")
	if cleaned == "" {
		return "", errors.New("未配置上游 BASE_URL")
	}
	u, err := url.Parse(cleaned)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return "", fmt.Errorf("BASE_URL 必须包含协议和主机,例如 https://example.com/v1")
	}
	if strings.EqualFold(u.Scheme, "http") && !isLoopbackHost(u.Hostname()) {
		return "", fmt.Errorf("拒绝使用非 TLS 上游: %s。只有 localhost / 127.0.0.1 / ::1 允许 http://", cleaned)
	}
	if !strings.EqualFold(u.Scheme, "http") && !strings.EqualFold(u.Scheme, "https") {
		return "", errors.New("BASE_URL 仅支持 http:// 或 https://")
	}
	if !strings.HasSuffix(cleaned, "/v1") {
		cleaned += "/v1"
	}
	return cleaned, nil
}

func isLoopbackHost(host string) bool {
	if strings.EqualFold(host, "localhost") || strings.HasSuffix(strings.ToLower(host), ".localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func intEnv(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	var value int
	if _, err := fmt.Sscanf(raw, "%d", &value); err != nil || value < 0 {
		return fallback
	}
	return value
}

func newTaskID() string {
	var b [2]byte
	if _, err := rand.Read(b[:]); err != nil {
		return time.Now().Format("20060102-150405") + "-0000"
	}
	return time.Now().Format("20060102-150405") + "-" + hex.EncodeToString(b[:])
}

func metadataMode(mode string) string {
	if mode == "generate" {
		return "text-to-image"
	}
	return "image-edit"
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func assertWritable(dir string) error {
	test := filepath.Join(dir, ".image-studio-write-test")
	if err := os.WriteFile(test, []byte("ok"), 0o600); err != nil {
		return fmt.Errorf("输出目录不可写，请检查权限: %w", err)
	}
	_ = os.Remove(test)
	return nil
}

func isSupportedImagePath(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".png", ".jpg", ".jpeg", ".webp":
		return true
	default:
		return false
	}
}

func mimeForPath(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".webp":
		return "image/webp"
	default:
		return "application/octet-stream"
	}
}

func modelFamily(model string) string {
	normalized := strings.ToLower(strings.TrimSpace(model))
	switch {
	case strings.HasPrefix(normalized, "dall-e-2"):
		return "dalle2"
	case strings.HasPrefix(normalized, "dall-e-3"):
		return "dalle3"
	case strings.HasPrefix(normalized, "gpt-image"), strings.HasPrefix(normalized, "chatgpt-image"):
		return "gpt-image"
	default:
		return "other"
	}
}

func supportsResponseFormat(model, mode string) bool {
	family := modelFamily(model)
	if mode == "edit" {
		return family == "dalle2"
	}
	return family == "dalle2" || family == "dalle3"
}

func isRetryableStatus(status int, err error) bool {
	if status == http.StatusTooManyRequests || status == http.StatusBadGateway || status == http.StatusServiceUnavailable || status == http.StatusGatewayTimeout || status == 524 {
		return true
	}
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "timeout") || strings.Contains(msg, "connection reset") || strings.Contains(msg, "eof") || strings.Contains(msg, "deadline exceeded")
}
