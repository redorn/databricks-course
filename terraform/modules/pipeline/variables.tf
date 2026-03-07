variable "environment"       { type = string }
variable "catalog"           { type = string }
variable "raw_schema"        { type = string }
variable "s3_landing_path"   { type = string }
variable "wheel_volume_path" {
  description = "UC volume path where the Python wheel is stored"
  type        = string
}

variable "source_filter" {
  description = "Restrict pipeline to one source system; empty = all"
  type        = string
  default     = ""
}

variable "entity_filter" {
  description = "Restrict pipeline to one entity; empty = all"
  type        = string
  default     = ""
}
