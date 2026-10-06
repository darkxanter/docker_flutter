variable "FLUTTER_CHANNEL" { default = "" }
variable "FLUTTER_VERSION" { default = "" }
variable "FLUTTER_REVISION" { default = "" }
variable "FLUTTER_URL" { default = "https://github.com/flutter/flutter.git" }
variable "IMAGE_REPOSITORY" { default = "xanter/flutter" }
variable "IMAGE_TAG" {
  default = FLUTTER_VERSION != "" ? FLUTTER_VERSION : (FLUTTER_CHANNEL != "" ? FLUTTER_CHANNEL : "stable")
}
variable "IMAGE_MINOR_TAG" { default = "" }
variable "UBUNTU_VERSION" { default = "24.04" }
variable "ANDROID_SDK_TOOLS_VERSION" { default = "11076708" }
variable "ANDROID_PLATFORM_VERSION" { default = "36" }
variable "ANDROID_BUILD_TOOLS_VERSION" { default = "36.0.0" }
variable "CI_CACHE" { default = "false" }

function "image_tags" {
  params = [suffix]
  result = compact([
    "${IMAGE_REPOSITORY}:${IMAGE_TAG}${suffix}",
    IMAGE_MINOR_TAG != "" ? "${IMAGE_REPOSITORY}:${IMAGE_MINOR_TAG}${suffix}" : ""
  ])
}

function "cache_source" {
  params = [variant]
  result = CI_CACHE == "true" ? ["type=gha,version=2,scope=flutter-${variant}"] : []
}

function "cache_destination" {
  params = [variant]
  result = CI_CACHE == "true" ? ["type=gha,version=2,scope=flutter-${variant},mode=max"] : []
}

group "default" {
  targets = ["base", "web", "android", "android-warmed"]
}

target "_common" {
  context = "."
  platforms = ["linux/amd64"]
  args = {
    FLUTTER_CHANNEL = FLUTTER_CHANNEL
    FLUTTER_VERSION = FLUTTER_VERSION
  }
  labels = {
    "org.opencontainers.image.version" = IMAGE_TAG
  }
}

target "base" {
  inherits = ["_common"]
  dockerfile = "dockerfiles/flutter.dockerfile"
  tags = image_tags("")
  args = {
    UBUNTU_VERSION = UBUNTU_VERSION
    FLUTTER_REVISION = FLUTTER_REVISION
    FLUTTER_URL = FLUTTER_URL
  }
  cache-from = cache_source("base")
  cache-to = cache_destination("base")
}

target "web" {
  inherits = ["_common"]
  dockerfile = "dockerfiles/flutter_web.dockerfile"
  contexts = { flutter-base = "target:base" }
  args = { BASE_IMAGE = "flutter-base" }
  tags = image_tags("-web")
  cache-from = cache_source("web")
  cache-to = cache_destination("web")
}

target "android" {
  inherits = ["_common"]
  dockerfile = "dockerfiles/flutter_android.dockerfile"
  contexts = { flutter-base = "target:base" }
  args = {
    BASE_IMAGE = "flutter-base"
    UBUNTU_VERSION = UBUNTU_VERSION
    ANDROID_SDK_TOOLS_VERSION = ANDROID_SDK_TOOLS_VERSION
    ANDROID_PLATFORM_VERSION = ANDROID_PLATFORM_VERSION
    ANDROID_BUILD_TOOLS_VERSION = ANDROID_BUILD_TOOLS_VERSION
  }
  tags = image_tags("-android")
  cache-from = cache_source("android")
  cache-to = cache_destination("android")
}

target "android-warmed" {
  inherits = ["_common"]
  dockerfile = "dockerfiles/flutter_android_warmed.dockerfile"
  contexts = { flutter-android = "target:android" }
  args = { BASE_IMAGE = "flutter-android" }
  tags = image_tags("-android-warmed")
  cache-from = cache_source("android-warmed")
  cache-to = cache_destination("android-warmed")
}
