# Artefactos de ejemplo

`s3bucket.tar.gz` viene del repositorio original de AWS
(`aws-samples/service-catalog-engine-for-terraform-os`, Apache-2.0) y es el **fixture**
que usan los tests de `lambda-functions/terraform_open_source_parameter_parser`:

```go
const TestS3BucketArtifactPath = "../../sample-provisioning-artifacts/s3bucket.tar.gz"
```

Sin el, `TestConfigFetcherFetchHappy` y `TestConfigFetcherFetchWithEmptyLaunchRoleHappy`
fallan. Se versiona a proposito, pese a la regla general de no versionar `*.tar.gz`:
ver la excepcion en `.gitignore`.
