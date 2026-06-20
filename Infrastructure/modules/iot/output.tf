data "aws_iot_endpoint" "iot_endpoint" {
  endpoint_type = "iot:Data-ATS"
}

output "iot_endpoint_url" {
  description = "The endpoint URL the Python simulator will connect to"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
}
