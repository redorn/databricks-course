module "catalog" {
  source = "./modules/catalog"

  catalog                = var.catalog
  landing_schema         = var.landing_schema
  raw_schema             = var.raw_schema
  s3_landing_path        = var.s3_landing_path
  environment            = var.environment
  metastore_storage_root = var.metastore_storage_root
}

module "pipeline" {
  source     = "./modules/pipeline"
  depends_on = [module.catalog]

  environment      = var.environment
  catalog          = var.catalog
  raw_schema       = var.raw_schema
  s3_landing_path  = var.s3_landing_path
  wheel_volume_path = module.catalog.wheel_volume_path
}

module "jobs" {
  source     = "./modules/jobs"
  depends_on = [module.catalog, module.pipeline]

  environment       = var.environment
  catalog           = var.catalog
  raw_schema        = var.raw_schema
  landing_schema    = var.landing_schema
  s3_landing_path   = var.s3_landing_path
  spark_version     = var.spark_version
  pipeline_id       = module.pipeline.pipeline_id
  wheel_volume_path = module.catalog.wheel_volume_path
}
