# --------------------------------------------------
# Simple GKE Cluster: 3 nodes, private, VPC-native
# --------------------------------------------------

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "7.8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  credentials = "/root/terraform-backend-key.json"
}

# -------------------------------
# Variables (edit or use .tfvars)
# -------------------------------
variable "project_id" { 
  type    = string
  default = "driver-team"
}

variable "region" {
  type    = string
  default = "asia-southeast1"
}

# -------------------------------
# VPC + Subnet (with secondary ranges)
# -------------------------------
resource "google_compute_network" "vpc" {
  name                    = "gke-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# -------------------------------
# GKE Cluster
# -------------------------------
resource "google_container_cluster" "gke" {
  name     = "gke-cluster-1"
  location = var.region

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native networking
  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.vpc.name
  subnetwork      = google_compute_subnetwork.subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster (control plane not public)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  # Allow your IP to access control plane (optional)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = "203.211.111.126/32"  # ← Replace with your IP or VPC CIDR
      display_name = "home-ip"
    }
  }

  # Workload Identity (recommended)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# -------------------------------
# Node Pool: 3 nodes
# -------------------------------
resource "google_container_node_pool" "nodes" {
  name       = "node-pool-1"
  location   = var.region
  cluster    = google_container_cluster.gke.name
  node_count = 3

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}