/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ModelDeploymentSpec is what a product team asks the platform for: a model,
// an engine, and how many replicas. Everything else - the Deployment, the
// Service, the ServiceMonitor, probes, metrics - is the platform's problem,
// which is to say this operator's.
type ModelDeploymentSpec struct {
	// Model is the model to serve, e.g. "Qwen/Qwen2.5-0.5B-Instruct".
	// +kubebuilder:validation:MinLength=1
	Model string `json:"model"`

	// Engine serves the model. "vllm" runs the real vLLM CPU backend;
	// "mock" runs a tiny built-in stand-in that is cheap enough for
	// drills and tests.
	// +kubebuilder:validation:Enum=vllm;mock
	// +kubebuilder:default=vllm
	Engine string `json:"engine,omitempty"`

	// Replicas of the serving pod.
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:default=1
	Replicas *int32 `json:"replicas,omitempty"`

	// MaxModelLen caps the context length (vllm only).
	// +kubebuilder:default=2048
	MaxModelLen *int32 `json:"maxModelLen,omitempty"`

	// Resources for the serving container. Defaults suit the lab's
	// CPU backend; unset means the engine's own defaults.
	// +optional
	Resources *corev1.ResourceRequirements `json:"resources,omitempty"`
}

// ModelDeploymentStatus is the operator's answer: how the serving stack is
// doing, summarised in conditions the way the rest of the ecosystem expects.
type ModelDeploymentStatus struct {
	// Conditions: "Ready" means the requested replicas answer their
	// readiness probe; "Progressing" means a rollout is under way.
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ReadyReplicas from the owned Deployment.
	// +optional
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`

	// Endpoint is the in-cluster URL of the OpenAI-compatible API.
	// +optional
	Endpoint string `json:"endpoint,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:shortName=mdep
// +kubebuilder:printcolumn:name="Model",type=string,JSONPath=`.spec.model`
// +kubebuilder:printcolumn:name="Engine",type=string,JSONPath=`.spec.engine`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=`.status.readyReplicas`

// ModelDeployment is the platform's interface for serving a model.
type ModelDeployment struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ModelDeploymentSpec   `json:"spec,omitempty"`
	Status ModelDeploymentStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ModelDeploymentList contains a list of ModelDeployment
type ModelDeploymentList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ModelDeployment `json:"items"`
}

func init() {
	objectTypes = append(objectTypes, &ModelDeployment{}, &ModelDeploymentList{})
}
