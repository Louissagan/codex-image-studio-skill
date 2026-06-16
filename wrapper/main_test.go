package main

import (
	"os"
	"testing"
)

func TestResolveProvider(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		provider string
		baseURL  string
		want     string
		wantErr  bool
	}{
		{
			name:    "auto runninghub host",
			baseURL: "https://www.runninghub.cn/call-api/api-detail/2046503667076751361",
			want:    providerRunningHub,
		},
		{
			name:    "auto openai compatible",
			baseURL: "https://api.openai.com/v1",
			want:    providerOpenAI,
		},
		{
			name:     "explicit runninghub",
			provider: providerRunningHub,
			baseURL:  "https://example.com/proxy",
			want:     providerRunningHub,
		},
		{
			name:     "invalid provider",
			provider: "bad",
			baseURL:  "https://api.openai.com/v1",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := resolveProvider(tt.provider, tt.baseURL)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("expected error")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("provider = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestRunningHubApplyDefaultsSelectsModeEndpoint(t *testing.T) {
	t.Parallel()

	generateCfg := config{
		Provider: providerRunningHub,
		Mode:     "generate",
		Prompt:   "make an image",
		BaseURL:  "https://www.runninghub.cn",
		APIKey:   "test-key",
	}
	if err := generateCfg.applyDefaults(); err != nil {
		t.Fatalf("generate applyDefaults: %v", err)
	}
	if generateCfg.Model != runningHubGPTImage2TextEndpoint {
		t.Fatalf("generate model = %q, want %q", generateCfg.Model, runningHubGPTImage2TextEndpoint)
	}

	input := t.TempDir() + "/source.png"
	if err := os.WriteFile(input, []byte("not a real png, only existence is validated here"), 0o600); err != nil {
		t.Fatalf("write input: %v", err)
	}
	editCfg := config{
		Provider: providerRunningHub,
		Mode:     "edit",
		Prompt:   "edit image",
		Inputs:   []string{input},
		BaseURL:  "https://www.runninghub.cn",
		APIKey:   "test-key",
	}
	if err := editCfg.applyDefaults(); err != nil {
		t.Fatalf("edit applyDefaults: %v", err)
	}
	if editCfg.Model != runningHubGPTImage2EditEndpoint {
		t.Fatalf("edit model = %q, want %q", editCfg.Model, runningHubGPTImage2EditEndpoint)
	}
}

func TestNormalizeBaseURL(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		raw      string
		provider string
		want     string
	}{
		{
			name:     "openai appends v1",
			raw:      "https://api.example.com",
			provider: providerOpenAI,
			want:     "https://api.example.com/v1",
		},
		{
			name:     "openai keeps v1",
			raw:      "https://api.example.com/v1/",
			provider: providerOpenAI,
			want:     "https://api.example.com/v1",
		},
		{
			name:     "runninghub detail URL becomes origin",
			raw:      "https://www.runninghub.cn/call-api/api-detail/2046503667076751361",
			provider: providerRunningHub,
			want:     "https://www.runninghub.cn",
		},
		{
			name:     "runninghub openapi suffix trimmed",
			raw:      "https://proxy.example.com/openapi/v2",
			provider: providerRunningHub,
			want:     "https://proxy.example.com",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := normalizeBaseURL(tt.raw, tt.provider)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("baseURL = %q, want %q", got, tt.want)
			}
		})
	}
}
