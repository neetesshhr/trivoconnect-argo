# trivoconnect-argo

kubectl get secret --namespace monitoring loki-stack -o jsonpath="{.data.admin-password}" | base64 --decode ; echo