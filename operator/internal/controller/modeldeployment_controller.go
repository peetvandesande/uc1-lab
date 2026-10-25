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

package controller

import (
	"context"
	"fmt"
	"os"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	servingv1alpha1 "github.com/peetvandesande/uc1-lab/operator/api/v1alpha1"
)

const (
	// finalizerName marks that this controller wants a word before a
	// ModelDeployment goes away. The owned objects would be garbage
	// collected through their owner references anyway; the finalizer is
	// where cleanup of anything *outside* the cluster would live, and it
	// is the mechanism drill 12 wedges open.
	finalizerName = "serving.uc1.home/finalizer"

	defaultVllmImage = "public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.29.0"
	defaultMockImage = "python:3.13-slim"

	// the mock engine: an OpenAI-shaped answering machine, small enough
	// to inline, so the engine needs no image build
	mockServer = `
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def _send(self, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        if self.path == "/metrics":
            self._send("# TYPE mock_up gauge\nmock_up 1\n", "text/plain")
        elif self.path == "/v1/models":
            self._send({"object": "list", "data": [{"id": MODEL, "object": "model"}]})
        else:
            self._send({"status": "ok"})
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self._send({"object": "chat.completion", "model": MODEL, "choices": [
            {"index": 0, "finish_reason": "stop",
             "message": {"role": "assistant", "content": "mock answer from " + MODEL}}]})
    def log_message(self, *a): pass
import os
MODEL = os.environ.get("MODEL", "mock")
http.server.ThreadingHTTPServer(("", 8000), H).serve_forever()
`
)

// ModelDeploymentReconciler reconciles a ModelDeployment object
type ModelDeploymentReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=serving.uc1.home,resources=modeldeployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=serving.uc1.home,resources=modeldeployments/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=serving.uc1.home,resources=modeldeployments/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=monitoring.coreos.com,resources=servicemonitors,verbs=get;list;watch;create;update;patch;delete

// Reconcile drives the world towards the ModelDeployment's spec: one
// Deployment, one Service and one ServiceMonitor per instance, owned by it,
// and a status that tells the truth about them.
func (r *ModelDeploymentReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	var md servingv1alpha1.ModelDeployment
	if err := r.Get(ctx, req.NamespacedName, &md); err != nil {
		// Deleted between the event and now: nothing to do, the owner
		// references take the children with it
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// Deletion: run whatever cleanup the finalizer guards, then let go
	if !md.DeletionTimestamp.IsZero() {
		if controllerutil.ContainsFinalizer(&md, finalizerName) {
			// External cleanup would happen here (billing records, a
			// model cache on shared storage, a DNS name, ...)
			log.Info("cleaning up before deletion", "model", md.Spec.Model)
			controllerutil.RemoveFinalizer(&md, finalizerName)
			if err := r.Update(ctx, &md); err != nil {
				return ctrl.Result{}, err
			}
		}
		return ctrl.Result{}, nil
	}

	if !controllerutil.ContainsFinalizer(&md, finalizerName) {
		controllerutil.AddFinalizer(&md, finalizerName)
		if err := r.Update(ctx, &md); err != nil {
			return ctrl.Result{}, err
		}
	}

	// The children, each created or patched to match the spec
	deploy, err := r.reconcileDeployment(ctx, &md)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("deployment: %w", err)
	}
	if err := r.reconcileService(ctx, &md); err != nil {
		return ctrl.Result{}, fmt.Errorf("service: %w", err)
	}
	if err := r.reconcileServiceMonitor(ctx, &md); err != nil {
		// The CRD may not be installed (module 20); degrade rather than fail
		if meta.IsNoMatchError(err) {
			log.Info("monitoring.coreos.com not installed; skipping the ServiceMonitor")
		} else {
			return ctrl.Result{}, fmt.Errorf("servicemonitor: %w", err)
		}
	}

	// Status: Ready when every requested replica is
	want := int32(1)
	if md.Spec.Replicas != nil {
		want = *md.Spec.Replicas
	}
	ready := deploy.Status.ReadyReplicas
	cond := metav1.Condition{
		Type:               "Ready",
		Status:             metav1.ConditionFalse,
		Reason:             "RolloutInProgress",
		Message:            fmt.Sprintf("%d of %d replicas ready", ready, want),
		ObservedGeneration: md.Generation,
	}
	if ready >= want {
		cond.Status = metav1.ConditionTrue
		cond.Reason = "AllReplicasReady"
	}
	meta.SetStatusCondition(&md.Status.Conditions, cond)
	md.Status.ReadyReplicas = ready
	md.Status.Endpoint = fmt.Sprintf("http://%s.%s.svc:8000/v1", md.Name, md.Namespace)
	if err := r.Status().Update(ctx, &md); err != nil {
		if errors.IsConflict(err) {
			return ctrl.Result{Requeue: true}, nil
		}
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

func labels(md *servingv1alpha1.ModelDeployment) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":       md.Name,
		"app.kubernetes.io/managed-by": "uc1-operator",
		"uc1.home/data-residency":      "eu",
	}
}

func (r *ModelDeploymentReconciler) reconcileDeployment(ctx context.Context, md *servingv1alpha1.ModelDeployment) (*appsv1.Deployment, error) {
	deploy := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: md.Name, Namespace: md.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, deploy, func() error {
		deploy.Labels = labels(md)
		deploy.Spec.Replicas = md.Spec.Replicas
		deploy.Spec.Selector = &metav1.LabelSelector{MatchLabels: map[string]string{
			"app.kubernetes.io/name": md.Name,
		}}
		deploy.Spec.Template.Labels = labels(md)
		deploy.Spec.Template.Spec.Containers = []corev1.Container{r.container(md)}
		deploy.Spec.Template.Spec.Volumes = []corev1.Volume{{
			Name: "cache",
			VolumeSource: corev1.VolumeSource{
				EmptyDir: &corev1.EmptyDirVolumeSource{
					SizeLimit: resource.NewQuantity(5<<30, resource.BinarySI),
				},
			},
		}}
		return controllerutil.SetControllerReference(md, deploy, r.Scheme)
	})
	return deploy, err
}

func (r *ModelDeploymentReconciler) container(md *servingv1alpha1.ModelDeployment) corev1.Container {
	c := corev1.Container{
		Name:  "server",
		Ports: []corev1.ContainerPort{{Name: "http", ContainerPort: 8000}},
		ReadinessProbe: &corev1.Probe{
			ProbeHandler: corev1.ProbeHandler{
				HTTPGet: &corev1.HTTPGetAction{Path: "/health", Port: intstr.FromString("http")},
			},
			InitialDelaySeconds: 10,
			PeriodSeconds:       10,
			FailureThreshold:    60, // model downloads take a while
		},
	}
	if md.Spec.Resources != nil {
		c.Resources = *md.Spec.Resources
	}

	switch md.Spec.Engine {
	case "mock":
		c.Image = envOr("UC1_MOCK_IMAGE", defaultMockImage)
		c.Command = []string{"python", "-c", mockServer}
		c.Env = []corev1.EnvVar{{Name: "MODEL", Value: md.Spec.Model}}
	default: // vllm
		maxLen := int32(2048)
		if md.Spec.MaxModelLen != nil {
			maxLen = *md.Spec.MaxModelLen
		}
		c.Image = envOr("UC1_VLLM_IMAGE", defaultVllmImage)
		c.Args = []string{
			"--model=" + md.Spec.Model,
			fmt.Sprintf("--max-model-len=%d", maxLen),
			"--dtype=bfloat16",
		}
		c.Env = []corev1.EnvVar{{Name: "VLLM_CPU_KVCACHE_SPACE", Value: "4"}}
		c.VolumeMounts = []corev1.VolumeMount{{Name: "cache", MountPath: "/root/.cache/huggingface"}}
		if md.Spec.Resources == nil {
			c.Resources = corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse("4"),
					corev1.ResourceMemory: resource.MustParse("8Gi"),
				},
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse("8"),
					corev1.ResourceMemory: resource.MustParse("12Gi"),
				},
			}
		}
	}
	return c
}

func (r *ModelDeploymentReconciler) reconcileService(ctx context.Context, md *servingv1alpha1.ModelDeployment) error {
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: md.Name, Namespace: md.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, svc, func() error {
		svc.Labels = labels(md)
		svc.Spec.Selector = map[string]string{"app.kubernetes.io/name": md.Name}
		svc.Spec.Ports = []corev1.ServicePort{{
			Name:       "http",
			Port:       8000,
			TargetPort: intstr.FromString("http"),
		}}
		return controllerutil.SetControllerReference(md, svc, r.Scheme)
	})
	return err
}

// reconcileServiceMonitor uses unstructured on purpose: the CRD belongs to
// another operator and may be absent, and depending on its Go module for two
// fields is not worth it.
func (r *ModelDeploymentReconciler) reconcileServiceMonitor(ctx context.Context, md *servingv1alpha1.ModelDeployment) error {
	sm := &unstructured.Unstructured{}
	sm.SetGroupVersionKind(schema.GroupVersionKind{
		Group: "monitoring.coreos.com", Version: "v1", Kind: "ServiceMonitor",
	})
	sm.SetName(md.Name)
	sm.SetNamespace(md.Namespace)
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, sm, func() error {
		sm.SetLabels(labels(md))
		if err := unstructured.SetNestedMap(sm.Object, map[string]any{
			"selector": map[string]any{
				"matchLabels": map[string]any{"app.kubernetes.io/name": md.Name},
			},
			"endpoints": []any{
				map[string]any{"port": "http", "path": "/metrics", "interval": "15s"},
			},
		}, "spec"); err != nil {
			return err
		}
		return controllerutil.SetControllerReference(md, sm, r.Scheme)
	})
	return err
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// SetupWithManager sets up the controller with the Manager. Owns() makes a
// change to any child queue its parent for reconciliation - that is how a
// deleted Service "heals" and how replica counts flow into status.
func (r *ModelDeploymentReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&servingv1alpha1.ModelDeployment{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Named("modeldeployment").
		Complete(r)
}
