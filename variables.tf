variable "access-key" {
  description = "Access key for AWS Account"
  type        = string
  sensitive   = true
}

variable "secret-key" {
  description = "Secret key for AWS Account"
  type        = string
  sensitive   = true
}

variable "site-domain" {
  description = "Domain of main website (ex. eshaanm.com)"
  type        = string
}

variable "site-redirect" {
  description = "site that will be redirected to main website (ex. eshaanm.com)"
  default     = null
  type        = string
}

variable "tags" {
  description = "Tags added to resources"
  default     = {}
  type        = map(string)
}

variable "aws-region" {
  description = "region to provision resources in"
  default = "us-east-1"
  type        = string
}

variable "sendgrid-api-key" {
  description = "API Key for Sendgrid E-Mail functionality"
  type = string
  sensitive = true
}

variable "from-address" {
  description = "E-mail address that the e-mail will come from"
  type = string
}

variable "sendgrid-template-id" {
  description = "The id of the template being used by Sendgrid"
}

variable "redirectlink" {
  type = string
  description = "link that website will redirect to once e-mail has been sent"
  default = "https://eshaanm.com"
}