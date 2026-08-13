variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "ssh_user" {
  type    = string
  default = "simone"
}

variable "ssh_pubkey_path" {
  type    = string
  default = "~/.ssh/f2lab.pub"
}

variable "my_ip" {
  type = string
}

variable "repo_url" {
  type    = string
  default = "https://github.com/dangelo-simone/stage-labs.git"
}
