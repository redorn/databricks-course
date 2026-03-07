module "catalog" {
  source = "./modules/catalog"

  catalog         = var.catalog
  landing_schema  = var.landing_schema
  raw_schema      = var.raw_schema
  s3_landing_path = var.s3_landing_path
  environment     = var.environment
}

module "pipeline" {
  source     = "./modules/pipeline"
  depends_on = [module.catalog]

  environment     = var.environment
  catalog         = var.catalog
  raw_schema      = var.raw_schema
  s3_landing_path = var.s3_landing_path
  node_type_id    = var.node_type_id
  max_workers     = var.max_workers
}

module "jobs" {
  source     = "./modules/jobs"
  depends_on = [module.catalog, module.pipeline]

  environment     = var.environment
  catalog         = var.catalog
  raw_schema      = var.raw_schema
  landing_schema  = var.landing_schema
  s3_landing_path = var.s3_landing_path
  spark_version   = var.spark_version
  node_type_id    = var.node_type_id
  pipeline_id     = module.pipeline.pipeline_id
}
