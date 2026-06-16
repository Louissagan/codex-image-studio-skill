package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	runningHubGPTImage2TextEndpoint = "/rhart-image-g-2-official/text-to-image"
	runningHubGPTImage2EditEndpoint = "/rhart-image-g-2/image-to-image"
)

type runningHubSKUResponse struct {
	Code int           `json:"code"`
	Msg  string        `json:"msg"`
	Data runningHubSKU `json:"data"`
}

type runningHubSKU struct {
	ID              string `json:"id"`
	CategoryType    string `json:"categoryType"`
	Owner           string `json:"owner"`
	RhEndpoint      string `json:"rhEndpoint"`
	InputConfigJSON string `json:"inputConfigJson"`
}

type runningHubField struct {
	Type           string             `json:"type"`
	FieldKey       string             `json:"fieldKey"`
	Title          string             `json:"title"`
	ParamDesc      string             `json:"paramDesc"`
	Required       bool               `json:"required"`
	DefaultValue   any                `json:"defaultValue"`
	MultipleInputs bool               `json:"multipleInputs"`
	MaxInputNum    int                `json:"maxInpuNum"`
	Options        []runningHubOption `json:"options"`
}

type runningHubOption struct {
	Value string `json:"value"`
}

type runningHubUploadResponse struct {
	Code    int    `json:"code"`
	Msg     string `json:"msg"`
	Message string `json:"message"`
	Data    struct {
		Type        string `json:"type"`
		DownloadURL string `json:"download_url"`
		URL         string `json:"url"`
		FileName    string `json:"fileName"`
		Size        string `json:"size"`
	} `json:"data"`
}

type runningHubTaskResponse struct {
	TaskID       string             `json:"taskId"`
	Status       string             `json:"status"`
	ErrorCode    string             `json:"errorCode"`
	ErrorMessage string             `json:"errorMessage"`
	FailedReason any                `json:"failedReason"`
	Usage        any                `json:"usage"`
	Results      []runningHubResult `json:"results"`
	ClientID     string             `json:"clientId"`
	PromptTips   string             `json:"promptTips"`
	Code         int                `json:"code"`
	Msg          string             `json:"msg"`
	Message      string             `json:"message"`
}

type runningHubTaskEnvelope struct {
	Code    int             `json:"code"`
	Msg     string          `json:"msg"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data"`
}

type runningHubResult struct {
	URL         string `json:"url"`
	FileURL     string `json:"fileUrl"`
	DownloadURL string `json:"download_url"`
	NodeID      string `json:"nodeId"`
	OutputType  string `json:"outputType"`
	Text        string `json:"text"`
}

func requestRunningHub(ctx context.Context, cfg config, logLine func(string, ...any)) (requestResult, error) {
	if cfg.Mask != "" {
		return requestResult{}, errors.New("Running Hub standard model requests do not support --mask in this wrapper yet")
	}

	sku, detailRaw, detailStatus, err := resolveRunningHubSKU(ctx, cfg)
	if err != nil {
		return requestResult{RawBody: detailRaw, StatusCode: detailStatus}, err
	}
	if err := validateRunningHubEndpointForMode(sku.RhEndpoint, cfg.Mode); err != nil {
		return requestResult{RawBody: detailRaw, StatusCode: detailStatus}, err
	}
	logLine("runninghub sku=%s endpoint=%s category=%s owner=%s", sku.ID, sku.RhEndpoint, sku.CategoryType, sku.Owner)

	fields, err := parseRunningHubFields(sku)
	if err != nil {
		return requestResult{RawBody: detailRaw, StatusCode: detailStatus}, err
	}

	imageURLs, err := uploadRunningHubInputs(ctx, cfg, logLine)
	if err != nil {
		return requestResult{}, err
	}

	payload, err := buildRunningHubPayload(cfg, fields, imageURLs)
	if err != nil {
		return requestResult{}, err
	}

	submitURL := runningHubAPIBase(cfg.BaseURL) + "/" + strings.TrimLeft(sku.RhEndpoint, "/")
	submitRaw, submitStatus, err := runningHubPostJSON(ctx, submitURL, cfg.APIKey, payload)
	if err != nil {
		return requestResult{RawBody: submitRaw, StatusCode: submitStatus}, err
	}

	task, err := parseRunningHubTask(submitRaw)
	if err != nil {
		return requestResult{RawBody: submitRaw, StatusCode: submitStatus}, err
	}
	if task.TaskID == "" {
		return requestResult{RawBody: submitRaw, StatusCode: submitStatus}, errors.New("Running Hub response did not include taskId")
	}
	logLine("runninghub task_id=%s submit_status=%s", task.TaskID, task.Status)

	finalRaw, finalStatus, finalTask, err := pollRunningHubTask(ctx, cfg, task.TaskID, logLine)
	if err != nil {
		if len(finalRaw) == 0 {
			finalRaw = submitRaw
			finalStatus = submitStatus
		}
		return requestResult{RawBody: finalRaw, StatusCode: finalStatus, UpstreamTaskID: task.TaskID}, err
	}

	outputURL, err := runningHubOutputURL(cfg.BaseURL, finalTask)
	if err != nil {
		return requestResult{RawBody: finalRaw, StatusCode: finalStatus, UpstreamTaskID: task.TaskID}, err
	}
	imageBytes, err := downloadImage(ctx, outputURL)
	if err != nil {
		return requestResult{RawBody: finalRaw, StatusCode: finalStatus, UpstreamTaskID: task.TaskID, OutputURL: outputURL}, err
	}

	return requestResult{
		ImageBytes:     imageBytes,
		RawBody:        finalRaw,
		StatusCode:     finalStatus,
		UpstreamTaskID: task.TaskID,
		OutputURL:      outputURL,
	}, nil
}

func resolveRunningHubSKU(ctx context.Context, cfg config) (runningHubSKU, []byte, int, error) {
	if endpoint, ok := runningHubEndpointFromModel(cfg.Model); ok {
		if !isAllowedRunningHubEndpoint(endpoint) {
			return runningHubSKU{}, nil, 0, fmt.Errorf("Running Hub endpoint %q is not allowed; allowed endpoints are %s and %s", endpoint, runningHubGPTImage2TextEndpoint, runningHubGPTImage2EditEndpoint)
		}
		sku, err := syntheticRunningHubSKU(endpoint)
		return sku, nil, 0, err
	}
	return fetchRunningHubSKU(ctx, cfg)
}

func fetchRunningHubSKU(ctx context.Context, cfg config) (runningHubSKU, []byte, int, error) {
	if !looksLikeRunningHubSKUID(cfg.Model) {
		return runningHubSKU{}, nil, 0, fmt.Errorf("Running Hub model must be a SKU id or one of %s, %s; got %q", runningHubGPTImage2TextEndpoint, runningHubGPTImage2EditEndpoint, cfg.Model)
	}
	endpoint := strings.TrimRight(cfg.BaseURL, "/") + "/api/sku/detail"
	raw, status, err := runningHubPostJSON(ctx, endpoint, cfg.APIKey, map[string]any{"id": cfg.Model})
	if err != nil {
		return runningHubSKU{}, raw, status, err
	}
	var parsed runningHubSKUResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return runningHubSKU{}, raw, status, fmt.Errorf("parse Running Hub SKU detail: %w", err)
	}
	if parsed.Code != 0 {
		return runningHubSKU{}, raw, status, fmt.Errorf("Running Hub SKU detail failed: code=%d msg=%s", parsed.Code, firstNonEmpty(parsed.Msg, "unknown"))
	}
	if parsed.Data.RhEndpoint == "" {
		return runningHubSKU{}, raw, status, errors.New("Running Hub SKU detail did not include rhEndpoint")
	}
	if !isAllowedRunningHubEndpoint(parsed.Data.RhEndpoint) {
		return runningHubSKU{}, raw, status, fmt.Errorf("Running Hub SKU endpoint %q is not allowed; allowed endpoints are %s and %s", normalizeRunningHubEndpoint(parsed.Data.RhEndpoint), runningHubGPTImage2TextEndpoint, runningHubGPTImage2EditEndpoint)
	}
	return parsed.Data, raw, status, nil
}

func syntheticRunningHubSKU(endpoint string) (runningHubSKU, error) {
	fields := runningHubFieldsForEndpoint(endpoint)
	if len(fields) == 0 {
		return runningHubSKU{}, fmt.Errorf("Running Hub endpoint %q is not supported", endpoint)
	}
	encoded, err := json.Marshal(fields)
	if err != nil {
		return runningHubSKU{}, err
	}
	return runningHubSKU{
		ID:              strings.TrimPrefix(endpoint, "/"),
		CategoryType:    "STANDARD_MODEL",
		Owner:           "THIRD",
		RhEndpoint:      endpoint,
		InputConfigJSON: string(encoded),
	}, nil
}

func runningHubFieldsForEndpoint(endpoint string) []runningHubField {
	common := []runningHubField{
		{Type: "STRING", FieldKey: "prompt", Title: "prompt", ParamDesc: "prompt", Required: true},
		{Type: "LIST", FieldKey: "aspectRatio", Title: "aspectRatio", ParamDesc: "aspectRatio", DefaultValue: "16:9", Options: runningHubAspectRatioOptions()},
		{Type: "LIST", FieldKey: "resolution", Title: "resolution", ParamDesc: "resolution", DefaultValue: "1k", Options: runningHubResolutionOptions()},
	}
	switch normalizeRunningHubEndpoint(endpoint) {
	case runningHubGPTImage2TextEndpoint:
		return common
	case runningHubGPTImage2EditEndpoint:
		imageField := runningHubField{Type: "IMAGE", FieldKey: "imageUrls", Title: "imageUrls", ParamDesc: "imageUrls", Required: true, MultipleInputs: true, MaxInputNum: 10}
		fields := []runningHubField{common[0], imageField}
		fields = append(fields, common[1:]...)
		return fields
	default:
		return nil
	}
}

func runningHubAspectRatioOptions() []runningHubOption {
	values := []string{"1:1", "2:3", "3:2", "4:5", "5:4", "4:3", "3:4", "16:9", "9:16", "21:9", "9:21", "2:1", "1:2", "3:1", "1:3"}
	options := make([]runningHubOption, 0, len(values))
	for _, value := range values {
		options = append(options, runningHubOption{Value: value})
	}
	return options
}

func runningHubResolutionOptions() []runningHubOption {
	return []runningHubOption{{Value: "1k"}, {Value: "2k"}, {Value: "4k"}}
}

func validateRunningHubEndpointForMode(rawEndpoint string, mode string) error {
	endpoint := normalizeRunningHubEndpoint(rawEndpoint)
	if !isAllowedRunningHubEndpoint(endpoint) {
		return fmt.Errorf("Running Hub endpoint %q is not allowed; allowed endpoints are %s and %s", endpoint, runningHubGPTImage2TextEndpoint, runningHubGPTImage2EditEndpoint)
	}
	if mode == "generate" && endpoint != runningHubGPTImage2TextEndpoint {
		return fmt.Errorf("Running Hub generate mode must use %s, got %s", runningHubGPTImage2TextEndpoint, endpoint)
	}
	if mode == "edit" && endpoint != runningHubGPTImage2EditEndpoint {
		return fmt.Errorf("Running Hub edit mode must use %s, got %s", runningHubGPTImage2EditEndpoint, endpoint)
	}
	return nil
}

func isAllowedRunningHubEndpoint(rawEndpoint string) bool {
	switch normalizeRunningHubEndpoint(rawEndpoint) {
	case runningHubGPTImage2TextEndpoint, runningHubGPTImage2EditEndpoint:
		return true
	default:
		return false
	}
}

func runningHubEndpointFromModel(value string) (string, bool) {
	if looksLikeRunningHubSKUID(value) {
		return "", false
	}
	endpoint := normalizeRunningHubEndpoint(value)
	if strings.Contains(endpoint, "/") && !looksLikeRunningHubSKUID(endpoint) {
		return endpoint, true
	}
	return "", false
}

func normalizeRunningHubEndpoint(raw string) string {
	cleaned := strings.TrimSpace(raw)
	if cleaned == "" {
		return ""
	}
	if strings.HasPrefix(cleaned, "http://") || strings.HasPrefix(cleaned, "https://") {
		parsed, err := url.Parse(cleaned)
		if err == nil {
			cleaned = parsed.Path
		}
	}
	cleaned = strings.TrimRight(cleaned, "/")
	cleaned = strings.TrimPrefix(cleaned, "/openapi/v2")
	if !strings.HasPrefix(cleaned, "/") {
		cleaned = "/" + cleaned
	}
	return cleaned
}

func parseRunningHubFields(sku runningHubSKU) ([]runningHubField, error) {
	if strings.TrimSpace(sku.InputConfigJSON) == "" {
		return nil, errors.New("Running Hub SKU detail did not include inputConfigJson")
	}
	var fields []runningHubField
	if err := json.Unmarshal([]byte(sku.InputConfigJSON), &fields); err != nil {
		return nil, fmt.Errorf("parse Running Hub inputConfigJson: %w", err)
	}
	if len(fields) == 0 {
		return nil, errors.New("Running Hub inputConfigJson contained no fields")
	}
	return fields, nil
}

func uploadRunningHubInputs(ctx context.Context, cfg config, logLine func(string, ...any)) ([]string, error) {
	if len(cfg.Inputs) == 0 {
		return nil, nil
	}
	urls := make([]string, 0, len(cfg.Inputs))
	for i, input := range cfg.Inputs {
		logLine("runninghub upload %d/%d path=%s", i+1, len(cfg.Inputs), input)
		url, err := uploadRunningHubFile(ctx, cfg, input)
		if err != nil {
			return nil, err
		}
		urls = append(urls, url)
	}
	return urls, nil
}

func uploadRunningHubFile(ctx context.Context, cfg config, path string) (string, error) {
	buf := &bytes.Buffer{}
	writer := multipart.NewWriter(buf)
	if err := addFilePart(writer, "file", path); err != nil {
		return "", err
	}
	if err := writer.Close(); err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, runningHubAPIBase(cfg.BaseURL)+"/media/upload/binary", buf)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	raw, status, err := doRawHTTP(req)
	if err != nil {
		return "", err
	}
	if status < 200 || status >= 300 {
		return "", fmt.Errorf("Running Hub upload returned HTTP %d: %s", status, string(raw))
	}

	var parsed runningHubUploadResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", fmt.Errorf("parse Running Hub upload response: %w", err)
	}
	if parsed.Code != 0 {
		return "", fmt.Errorf("Running Hub upload failed: code=%d msg=%s", parsed.Code, firstNonEmpty(parsed.Msg, parsed.Message, "unknown"))
	}
	rawURL := firstNonEmpty(parsed.Data.DownloadURL, parsed.Data.URL, parsed.Data.FileName)
	if strings.TrimSpace(rawURL) == "" {
		return "", errors.New("Running Hub upload response did not include download_url")
	}
	return resolveRunningHubURL(cfg.BaseURL, rawURL), nil
}

func buildRunningHubPayload(cfg config, fields []runningHubField, imageURLs []string) (map[string]any, error) {
	payload := map[string]any{}
	promptMapped := false
	imagesMapped := false

	for _, field := range fields {
		key := strings.TrimSpace(field.FieldKey)
		if key == "" {
			continue
		}
		value, ok, err := runningHubFieldValue(cfg, field, imageURLs)
		if err != nil {
			return nil, err
		}
		if !ok {
			continue
		}
		payload[key] = value
		if isRunningHubPromptField(field) {
			promptMapped = true
		}
		if isRunningHubImageField(field) {
			imagesMapped = true
		}
	}

	if !promptMapped {
		payload["prompt"] = cfg.Prompt
	}
	if len(imageURLs) > 0 && !imagesMapped {
		payload["imageUrls"] = imageURLs
	}
	return payload, nil
}

func runningHubFieldValue(cfg config, field runningHubField, imageURLs []string) (any, bool, error) {
	if isRunningHubPromptField(field) {
		return cfg.Prompt, true, nil
	}
	if isRunningHubImageField(field) {
		if len(imageURLs) == 0 {
			if field.Required {
				return nil, false, fmt.Errorf("Running Hub field %q requires --input images", field.FieldKey)
			}
			return nil, false, nil
		}
		if field.MultipleInputs || strings.HasSuffix(normalizeRunningHubFieldName(field.FieldKey), "s") {
			return imageURLs, true, nil
		}
		return imageURLs[0], true, nil
	}
	if isRunningHubAspectRatioField(field) {
		if cfg.AspectRatio != "" {
			return cfg.AspectRatio, true, nil
		}
		if derived := aspectRatioFromSize(cfg.Size); derived != "" && runningHubOptionAllows(field, derived) {
			return derived, true, nil
		}
		value, ok := runningHubDefault(field)
		return value, ok, nil
	}
	if isRunningHubResolutionField(field) {
		if cfg.Resolution != "" {
			return cfg.Resolution, true, nil
		}
		value, ok := runningHubDefault(field)
		return value, ok, nil
	}
	if isRunningHubQualityField(field) {
		if cfg.Quality != "" && !strings.EqualFold(cfg.Quality, "auto") {
			return cfg.Quality, true, nil
		}
		value, ok := runningHubDefault(field)
		return value, ok, nil
	}
	if value, ok := runningHubDefault(field); ok {
		return value, true, nil
	}
	if field.Required {
		return nil, false, fmt.Errorf("Running Hub field %q is required but has no mapped value", field.FieldKey)
	}
	return nil, false, nil
}

func runningHubDefault(field runningHubField) (any, bool) {
	if field.DefaultValue == nil {
		return nil, false
	}
	if value, ok := field.DefaultValue.(string); ok {
		value = strings.TrimSpace(value)
		if value == "" {
			return nil, false
		}
		return value, true
	}
	return field.DefaultValue, true
}

func pollRunningHubTask(ctx context.Context, cfg config, taskID string, logLine func(string, ...any)) ([]byte, int, runningHubTaskResponse, error) {
	queryURL := runningHubAPIBase(cfg.BaseURL) + "/query"
	payload := map[string]any{"taskId": taskID}
	var lastRaw []byte
	var lastStatus int
	var lastTask runningHubTaskResponse
	for {
		raw, status, err := runningHubPostJSON(ctx, queryURL, cfg.APIKey, payload)
		lastRaw = raw
		lastStatus = status
		if err != nil {
			return lastRaw, lastStatus, lastTask, err
		}
		task, err := parseRunningHubTask(raw)
		lastTask = task
		if err != nil {
			return lastRaw, lastStatus, lastTask, err
		}

		switch strings.ToUpper(strings.TrimSpace(task.Status)) {
		case "SUCCESS":
			return lastRaw, lastStatus, task, nil
		case "RUNNING", "QUEUED", "PENDING", "WAITING":
			logLine("runninghub task_id=%s status=%s", taskID, task.Status)
		default:
			return lastRaw, lastStatus, task, fmt.Errorf("Running Hub task failed: status=%s errorCode=%s errorMessage=%s", task.Status, task.ErrorCode, task.ErrorMessage)
		}

		select {
		case <-ctx.Done():
			return lastRaw, lastStatus, lastTask, ctx.Err()
		case <-time.After(5 * time.Second):
		}
	}
}

func parseRunningHubTask(raw []byte) (runningHubTaskResponse, error) {
	var task runningHubTaskResponse
	if err := json.Unmarshal(raw, &task); err != nil {
		return task, fmt.Errorf("parse Running Hub task response: %w", err)
	}
	if task.TaskID == "" && task.Status == "" && len(task.Results) == 0 {
		var envelope runningHubTaskEnvelope
		if err := json.Unmarshal(raw, &envelope); err == nil && len(envelope.Data) > 0 && string(envelope.Data) != "null" {
			var nested runningHubTaskResponse
			if err := json.Unmarshal(envelope.Data, &nested); err == nil && (nested.TaskID != "" || nested.Status != "" || len(nested.Results) > 0) {
				task = nested
				task.Code = envelope.Code
				task.Msg = firstNonEmpty(task.Msg, envelope.Msg)
				task.Message = firstNonEmpty(task.Message, envelope.Message)
			} else {
				var taskID string
				if err := json.Unmarshal(envelope.Data, &taskID); err == nil && strings.TrimSpace(taskID) != "" {
					task.TaskID = taskID
					task.Code = envelope.Code
					task.Msg = envelope.Msg
					task.Message = envelope.Message
				}
			}
		}
	}
	if task.Code != 0 {
		return task, fmt.Errorf("Running Hub task response failed: code=%d msg=%s", task.Code, firstNonEmpty(task.Msg, task.Message, "unknown"))
	}
	return task, nil
}

func runningHubOutputURL(baseURL string, task runningHubTaskResponse) (string, error) {
	if len(task.Results) == 0 {
		return "", errors.New("Running Hub task succeeded but returned no results")
	}
	for _, result := range task.Results {
		candidate := firstNonEmpty(result.URL, result.FileURL, result.DownloadURL)
		if strings.TrimSpace(candidate) != "" {
			return resolveRunningHubURL(baseURL, candidate), nil
		}
	}
	return "", errors.New("Running Hub task results did not include an image URL")
}

func runningHubPostJSON(ctx context.Context, endpoint string, apiKey string, payload any) ([]byte, int, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, 0, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)
	raw, status, err := doRawHTTP(req)
	if err != nil {
		return raw, status, err
	}
	if status < 200 || status >= 300 {
		return raw, status, fmt.Errorf("Running Hub returned HTTP %d: %s", status, string(raw))
	}
	return raw, status, nil
}

func doRawHTTP(req *http.Request) ([]byte, int, error) {
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return raw, resp.StatusCode, err
	}
	return raw, resp.StatusCode, nil
}

func runningHubAPIBase(baseURL string) string {
	return strings.TrimRight(baseURL, "/") + "/openapi/v2"
}

func resolveRunningHubURL(baseURL string, raw string) string {
	cleaned := strings.TrimSpace(raw)
	if cleaned == "" {
		return cleaned
	}
	if strings.HasPrefix(cleaned, "http://") || strings.HasPrefix(cleaned, "https://") || strings.HasPrefix(cleaned, "data:") {
		return cleaned
	}
	parsed, err := url.Parse(strings.TrimRight(baseURL, "/"))
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return cleaned
	}
	origin := parsed.Scheme + "://" + parsed.Host
	if strings.HasPrefix(cleaned, "//") {
		return parsed.Scheme + ":" + cleaned
	}
	if strings.HasPrefix(cleaned, "/") {
		return origin + cleaned
	}
	return origin + "/" + cleaned
}

func looksLikeRunningHubSKUID(value string) bool {
	value = strings.TrimSpace(value)
	if value == "" {
		return false
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func isRunningHubPromptField(field runningHubField) bool {
	name := normalizeRunningHubFieldName(firstNonEmpty(field.FieldKey, field.Title, field.ParamDesc))
	return strings.Contains(name, "prompt") || strings.Contains(name, "instruction")
}

func isRunningHubImageField(field runningHubField) bool {
	typeName := strings.ToUpper(strings.TrimSpace(field.Type))
	name := normalizeRunningHubFieldName(firstNonEmpty(field.FieldKey, field.Title, field.ParamDesc))
	return typeName == "IMAGE" || typeName == "COMMONMEDIA" || strings.Contains(name, "imageurl")
}

func isRunningHubAspectRatioField(field runningHubField) bool {
	name := normalizeRunningHubFieldName(firstNonEmpty(field.FieldKey, field.Title, field.ParamDesc))
	return strings.Contains(name, "aspectratio") || strings.Contains(name, "ratio")
}

func isRunningHubResolutionField(field runningHubField) bool {
	name := normalizeRunningHubFieldName(firstNonEmpty(field.FieldKey, field.Title, field.ParamDesc))
	return strings.Contains(name, "resolution")
}

func isRunningHubQualityField(field runningHubField) bool {
	name := normalizeRunningHubFieldName(firstNonEmpty(field.FieldKey, field.Title, field.ParamDesc))
	return strings.Contains(name, "quality")
}

func normalizeRunningHubFieldName(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	var b strings.Builder
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func runningHubOptionAllows(field runningHubField, value string) bool {
	if len(field.Options) == 0 {
		return true
	}
	for _, option := range field.Options {
		if strings.EqualFold(strings.TrimSpace(option.Value), strings.TrimSpace(value)) {
			return true
		}
	}
	return false
}

func aspectRatioFromSize(size string) string {
	size = strings.ToLower(strings.TrimSpace(size))
	if size == "" || size == "auto" {
		return ""
	}
	if strings.Contains(size, ":") && !strings.Contains(size, "x") {
		return size
	}
	parts := strings.Split(size, "x")
	if len(parts) != 2 {
		return ""
	}
	w, okW := parsePositiveInt(parts[0])
	h, okH := parsePositiveInt(parts[1])
	if !okW || !okH || w <= 0 || h <= 0 {
		return ""
	}
	g := gcd(w, h)
	return fmt.Sprintf("%d:%d", w/g, h/g)
}

func parsePositiveInt(value string) (int, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0, false
	}
	result := 0
	for _, r := range value {
		if r < '0' || r > '9' {
			return 0, false
		}
		result = result*10 + int(r-'0')
	}
	return result, result > 0
}

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	if a < 0 {
		return -a
	}
	if a == 0 {
		return 1
	}
	return a
}
