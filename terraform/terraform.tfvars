# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

gcp_project_id = "mosig-training"

service_account_path = "../project-sa.json"

region = "europe-west6"

zone = "europe-west6-b"

enable_autopilot = false

memorystore = false

namespace = "app"

tracing = false

logging = false

grafana_smtp_host = "sandbox.smtp.mailtrap.io:2525"

grafana_smtp_user = "3b2d2dac48881e"

grafana_smtp_password = "ff7cbfcfca5d30"