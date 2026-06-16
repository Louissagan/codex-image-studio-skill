package main

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestBuildRunningHubPayload(t *testing.T) {
	t.Parallel()

	cfg := config{
		Prompt:      "make it a polished product render",
		AspectRatio: "16:9",
		Resolution:  "1k",
	}
	fields := []runningHubField{
		{Type: "STRING", FieldKey: "prompt", Required: true},
		{Type: "IMAGE", FieldKey: "imageUrls", Required: true, MultipleInputs: true},
		{Type: "LIST", FieldKey: "aspectRatio", DefaultValue: "1:1"},
		{Type: "LIST", FieldKey: "resolution", DefaultValue: "2k"},
	}

	payload, err := buildRunningHubPayload(cfg, fields, []string{"https://example.com/a.png", "https://example.com/b.png"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := map[string]any{
		"prompt":      "make it a polished product render",
		"imageUrls":   []string{"https://example.com/a.png", "https://example.com/b.png"},
		"aspectRatio": "16:9",
		"resolution":  "1k",
	}
	if !reflect.DeepEqual(payload, want) {
		t.Fatalf("payload = %#v, want %#v", payload, want)
	}
}

func TestRunningHubEndpointRestrictions(t *testing.T) {
	t.Parallel()

	if err := validateRunningHubEndpointForMode(runningHubGPTImage2TextEndpoint, "generate"); err != nil {
		t.Fatalf("text endpoint should be valid for generate: %v", err)
	}
	if err := validateRunningHubEndpointForMode(runningHubGPTImage2EditEndpoint, "edit"); err != nil {
		t.Fatalf("edit endpoint should be valid for edit: %v", err)
	}
	if err := validateRunningHubEndpointForMode(runningHubGPTImage2EditEndpoint, "generate"); err == nil {
		t.Fatalf("edit endpoint should be rejected for generate")
	}
	if err := validateRunningHubEndpointForMode("/some-other-model/text-to-image", "generate"); err == nil {
		t.Fatalf("unexpected endpoint should be rejected")
	}
}

func TestRunningHubEndpointModelCreatesSyntheticSKU(t *testing.T) {
	t.Parallel()

	endpoint, ok := runningHubEndpointFromModel("https://www.runninghub.cn/openapi/v2/rhart-image-g-2-official/text-to-image")
	if !ok || endpoint != runningHubGPTImage2TextEndpoint {
		t.Fatalf("endpoint = %q ok=%v", endpoint, ok)
	}
	sku, err := syntheticRunningHubSKU(endpoint)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	fields, err := parseRunningHubFields(sku)
	if err != nil {
		t.Fatalf("unexpected parse error: %v", err)
	}
	for _, field := range fields {
		if field.FieldKey == "imageUrls" {
			t.Fatalf("text-to-image synthetic fields should not include imageUrls")
		}
	}
}

func TestBuildRunningHubPayloadRequiresImages(t *testing.T) {
	t.Parallel()

	_, err := buildRunningHubPayload(
		config{Prompt: "edit"},
		[]runningHubField{{Type: "IMAGE", FieldKey: "imageUrls", Required: true, MultipleInputs: true}},
		nil,
	)
	if err == nil {
		t.Fatalf("expected required image error")
	}
}

func TestParseRunningHubTaskEnvelope(t *testing.T) {
	t.Parallel()

	raw := []byte(`{"code":0,"msg":"success","data":{"taskId":"task-123","status":"SUCCESS","results":[{"url":"https://example.com/out.png"}]}}`)
	task, err := parseRunningHubTask(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if task.TaskID != "task-123" || task.Status != "SUCCESS" || len(task.Results) != 1 || task.Results[0].URL == "" {
		t.Fatalf("unexpected task: %#v", task)
	}
}

func TestParseRunningHubFieldsFromSKU(t *testing.T) {
	t.Parallel()

	fieldsJSON, err := json.Marshal([]runningHubField{
		{Type: "STRING", FieldKey: "prompt", Required: true},
		{Type: "IMAGE", FieldKey: "imageUrls", Required: true, MultipleInputs: true},
	})
	if err != nil {
		t.Fatalf("marshal fields: %v", err)
	}
	fields, err := parseRunningHubFields(runningHubSKU{InputConfigJSON: string(fieldsJSON)})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(fields) != 2 || fields[0].FieldKey != "prompt" || fields[1].FieldKey != "imageUrls" {
		t.Fatalf("unexpected fields: %#v", fields)
	}
}
