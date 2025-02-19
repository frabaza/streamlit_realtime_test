###################
# Configure Terraform
###################
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

###################
# Variables
###################
variable "project_id" {}
variable "region" {
  default = "us-central1"
}

# A separate variable for repository location (often same as region)
variable "repository_location" {
  default = "us-central1"
}

variable "container_image_name" {
  default = "streamlit-cloud-run"
}

###################
# Artifact Registry
###################
resource "google_artifact_registry_repository" "repo" {
  provider        = google-beta
  location        = var.repository_location
  repository_id   = "my-streamlit-repo"
  description     = "Docker repo for Streamlit app"
  format          = "DOCKER"
}

###################
# Build & Push Docker Image (Cloud Build)
###################
# This resource uses local docker context. 
# Make sure your "Dockerfile" is one directory up from this .tf file
# Or adjust the "dir" in the step accordingly.
resource "google_cloudbuild_build" "streamlit_build" {
  timeout = "1200s" # 20 minutes

  # The image name in Artifact Registry
  images = [
    "${google_artifact_registry_repository.repo.repository}/streamlit-cloud-run:latest"
  ]

  # Steps to build & push
  steps {
    name = "gcr.io/cloud-builders/docker"
    args = [
      "build",
      "-t",
      "${google_artifact_registry_repository.repo.repository}/${var.container_image_name}:latest",
      "."
    ]
  }

  steps {
    name = "gcr.io/cloud-builders/docker"
    args = [
      "push",
      "${google_artifact_registry_repository.repo.repository}/${var.container_image_name}:latest"
    ]
  }
  
  # The directory containing your Dockerfile 
  # (assuming Dockerfile is up one level from this main.tf)
  # If your Dockerfile is in the same level as main.tf, set dir = "."
  source {
    storage_source {
      bucket = null
      object = null
    }
    # For a local build, we can specify the dir, but often you'd supply Cloud Build 
    # with a GCS bucket or a Git source. This example is simplified.
    # If you run `terraform apply` from the same directory as your Dockerfile, 
    # you can set this to ".". 
    dir = ".."
  }
}

###################
# Deploy to Cloud Run
###################
resource "google_cloud_run_service" "streamlit_service" {
  name     = "streamlit-service"
  location = var.region

  template {
    spec {
      containers {
        image = "${google_artifact_registry_repository.repo.repository}/${var.container_image_name}:latest"
        resources {
          # For example, 512Mi memory
          limits = {
            memory = "512Mi"
          }
        }
        env {
          name  = "PORT"
          value = "8080"
        }
      }
    }
  }

  # Allow unauthenticated
  autogenerate_revision_name = true
}

###################
# IAM to allow public (unauthenticated) access
###################
resource "google_cloud_run_service_iam_member" "noauth" {
  location        = var.region
  project         = var.project_id
  service         = google_cloud_run_service.streamlit_service.name
  role            = "roles/run.invoker"
  member          = "allUsers"
}

###################
# Outputs
###################
output "cloud_run_url" {
  value = google_cloud_run_service.streamlit_service.status[0].url
  description = "The URL of the Cloud Run service"
}
