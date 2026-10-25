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

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	servingv1alpha1 "github.com/peetvandesande/uc1-lab/operator/api/v1alpha1"
)

var _ = Describe("ModelDeployment Controller", func() {
	const (
		resourceName      = "test-model"
		resourceNamespace = "default"
	)

	ctx := context.Background()
	nn := types.NamespacedName{Name: resourceName, Namespace: resourceNamespace}

	reconciler := func() *ModelDeploymentReconciler {
		return &ModelDeploymentReconciler{Client: k8sClient, Scheme: k8sClient.Scheme()}
	}

	// Reconcile twice: the first pass adds the finalizer and returns, the
	// requeued pass builds the children - like the real manager would
	reconcileTwice := func() {
		for range 2 {
			_, err := reconciler().Reconcile(ctx, reconcile.Request{NamespacedName: nn})
			Expect(err).NotTo(HaveOccurred())
		}
	}

	BeforeEach(func() {
		resource := &servingv1alpha1.ModelDeployment{
			ObjectMeta: metav1.ObjectMeta{Name: resourceName, Namespace: resourceNamespace},
			Spec: servingv1alpha1.ModelDeploymentSpec{
				Model:  "Qwen/Qwen2.5-0.5B-Instruct",
				Engine: "mock",
			},
		}
		Expect(k8sClient.Create(ctx, resource)).To(Succeed())
	})

	AfterEach(func() {
		resource := &servingv1alpha1.ModelDeployment{}
		if err := k8sClient.Get(ctx, nn, resource); err == nil {
			Expect(k8sClient.Delete(ctx, resource)).To(Succeed())
			// Run the deletion path so the finalizer is removed and the
			// object actually goes away (envtest has no GC)
			_, err := reconciler().Reconcile(ctx, reconcile.Request{NamespacedName: nn})
			Expect(err).NotTo(HaveOccurred())
		}
		Eventually(func() bool {
			return errors.IsNotFound(k8sClient.Get(ctx, nn, &servingv1alpha1.ModelDeployment{}))
		}).Should(BeTrue())
		// envtest does not garbage-collect the children; remove them so
		// the next test starts clean
		_ = k8sClient.Delete(ctx, &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: resourceName, Namespace: resourceNamespace}})
		_ = k8sClient.Delete(ctx, &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: resourceName, Namespace: resourceNamespace}})
	})

	It("creates an owned Deployment and Service", func() {
		reconcileTwice()

		deploy := &appsv1.Deployment{}
		Expect(k8sClient.Get(ctx, nn, deploy)).To(Succeed())
		Expect(deploy.OwnerReferences).To(HaveLen(1))
		Expect(deploy.OwnerReferences[0].Kind).To(Equal("ModelDeployment"))
		Expect(*deploy.OwnerReferences[0].Controller).To(BeTrue())
		Expect(deploy.Spec.Template.Spec.Containers[0].Env).To(ContainElement(
			corev1.EnvVar{Name: "MODEL", Value: "Qwen/Qwen2.5-0.5B-Instruct"}))

		svc := &corev1.Service{}
		Expect(k8sClient.Get(ctx, nn, svc)).To(Succeed())
		Expect(svc.Spec.Ports).To(HaveLen(1))
		Expect(svc.Spec.Ports[0].Port).To(Equal(int32(8000)))
	})

	It("adds the finalizer and reports status", func() {
		reconcileTwice()

		md := &servingv1alpha1.ModelDeployment{}
		Expect(k8sClient.Get(ctx, nn, md)).To(Succeed())
		Expect(md.Finalizers).To(ContainElement("serving.uc1.home/finalizer"))
		Expect(md.Status.Endpoint).To(Equal("http://test-model.default.svc:8000/v1"))
		Expect(md.Status.Conditions).NotTo(BeEmpty())
		Expect(md.Status.Conditions[0].Type).To(Equal("Ready"))
		// No kubelet in envtest, so nothing becomes ready
		Expect(md.Status.Conditions[0].Status).To(Equal(metav1.ConditionFalse))
	})

	It("puts a changed child back", func() {
		reconcileTwice()

		// Someone edits the Deployment behind the operator's back
		deploy := &appsv1.Deployment{}
		Expect(k8sClient.Get(ctx, nn, deploy)).To(Succeed())
		deploy.Spec.Template.Spec.Containers[0].Image = "nginx:latest"
		Expect(k8sClient.Update(ctx, deploy)).To(Succeed())

		reconcileTwice()

		Expect(k8sClient.Get(ctx, nn, deploy)).To(Succeed())
		Expect(deploy.Spec.Template.Spec.Containers[0].Image).To(Equal("python:3.13-slim"))
	})

	It("respects replica changes from the spec", func() {
		reconcileTwice()

		md := &servingv1alpha1.ModelDeployment{}
		Expect(k8sClient.Get(ctx, nn, md)).To(Succeed())
		three := int32(3)
		md.Spec.Replicas = &three
		Expect(k8sClient.Update(ctx, md)).To(Succeed())

		reconcileTwice()

		deploy := &appsv1.Deployment{}
		Expect(k8sClient.Get(ctx, nn, deploy)).To(Succeed())
		Expect(*deploy.Spec.Replicas).To(Equal(int32(3)))
	})
})
