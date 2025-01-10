## Deploying Online Boutique with Service Mesh

Inspired by the article ["Use Helm to simplify and secure the deployment of Online Boutique, with Service Mesh, GitOps, and more"](https://medium.com/google-cloud/online-boutiques-helm-chart-to-simplify-the-setup-of-advanced-scenarios-with-service-mesh-and-246119e46d53), we enhanced the deployment of the Online Boutique application by integrating a service mesh using Istio. 

### What is Istio and Service Mesh?
Istio is an open-source service mesh that simplifies managing communication between microservices in a distributed application. It provides features like traffic management, security, and observability by deploying sidecar proxies alongside application containers. These proxies handle communication between services, enabling consistent policies and monitoring without modifying the application code.

### Automation and Platform Independence
To ensure platform independence, we automated the deployment of Istio and Kiali using Ansible in the playbook [install-istio-flagger.yml](ansible/install-istio-flagger.yml). This approach allows us to deploy the application on any Kubernetes cluster without relying on platform-specific tools like Google Cloud’s Istio add-ons. 

### What is Kiali?
Kiali is a visualization tool for Istio that provides insights into the service mesh topology, traffic distribution, and application performance. It integrates seamlessly with Istio to help monitor and troubleshoot service mesh deployments.

### Maintaining Original Helm Chart Sidecars
We retained the original Sidecar definitions from the Helm chart. Below is an example of the Sidecar configuration for the frontend microservice:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  generation: 1
  labels:
    argocd.argoproj.io/instance: online-boutique
  name: frontend
  namespace: app
spec:
  egress:
  - hosts:
    - istio-system/*
    - ./adservice.app.svc.cluster.local
    - ./cartservice.app.svc.cluster.local
    - ./checkoutservice.app.svc.cluster.local
    - ./currencyservice.app.svc.cluster.local
    - ./productcatalogservice.app.svc.cluster.local
    - ./recommendationservice.app.svc.cluster.local
    - ./shippingservice.app.svc.cluster.local
    - ./opentelemetrycollector.app.svc.cluster.local
  workloadSelector:
    labels:
      app: frontend
```

this Sidecar defines how the service interacts with the rest of the mesh. This configuration:

1. **Controls Outbound Traffic:** It specifies the egress hosts that the frontend service can communicate with, including other services in the application (e.g., `adservice`, `cartservice`) and Istio system components.
2. **Ensures Security:** By restricting communication to defined hosts, it prevents unauthorized access and enforces security policies.
3. **Supports Service Mesh Operations:** Enables advanced Istio features like traffic routing, monitoring, and fault injection by ensuring all outbound traffic is routed through the mesh.

This approach ensures the frontend service communicates securely and efficiently with other components, leveraging Istio’s features to provide observability and traffic control.

### Purpose of Service Mesh and Usage Cases
Service meshes like Istio simplify managing complex microservices architectures by handling networking concerns such as:
- **Traffic Control:** Managing how requests are routed between services.
- **Observability:** Providing insights into traffic flow and service dependencies.
- **Security:** Enabling secure communication through mutual TLS (mTLS).

In the next section, we explore how service mesh features like traffic control are utilized for progressive delivery with canary releases.

## Canary Releases

### Manual Canary Deployment in Kubernetes

Manually implementing a canary deployment in Kubernetes involves deploying a new version of an application alongside the existing one and managing traffic distribution between them. This process typically includes:

1. **Creating a Separate Deployment**: Deploy the new version as a separate Deployment resource.

2. **Service Management**: Configure Services to route traffic to both the stable and canary versions.

3. **Traffic Splitting**: Manually adjust the number of replicas in each Deployment to control the proportion of traffic each version receives.

**Some limitations of Manual Canary Deployment**:

- **Inflexible Traffic Control**: Achieving precise traffic distribution, such as directing 1% of traffic to the canary version, requires a large number of replicas (e.g., 100 replicas for 1% traffic), which is resource-intensive and impractical.

- **Coupled Scaling and Traffic Management**: In Kubernetes, traffic distribution is inherently linked to the number of pod replicas. This coupling complicates scenarios where independent scaling and traffic routing are desired.

### Automated Canary Releases with Flagger, Istio, and ArgoCD

We implemented automated canary releases using the following tools:

1. **Flagger**: An open-source progressive delivery tool that automates canary deployments by analyzing metrics and triggering traffic shifts or rollbacks.

2. **Istio**: A service mesh that manages traffic distribution between primary and canary deployments and simplifies network-level operations.

3. **Kiali**: A visualization tool that provides a UI for monitoring and verifying traffic distribution between primary and canary deployments.

We automated the deployment of Istio, Flagger, and Kiali, along with the necessary configurations and components, to implement canary releases using the ansible playbook [install-istio-flagger.yml](ansible/install-istio-flagger.yml).

### Traffic Distribution using Istio

In our setup, Istio addresses the challenges of manual deployments by:

- **Decoupling Traffic Management from Scaling**: Istio separates traffic routing from deployment scaling, which allows for precise traffic control without the need for proportional scaling of replicas.

- **Fine-Grained Traffic Control**: Istio enables routing a specific percentage of traffic to the canary version without requiring a corresponding number of replicas, facilitating more efficient resource utilization.

- **Automated Rollbacks**: When integrated with Flagger, Istio can automatically revert to the stable version if the canary deployment exhibits issues, reducing downtime and manual intervention.

### Canary Releases Process in our Setup

1. A developer makes a change to the source code of a microservice and commits the update.

2. The CI pipeline builds the new container image and Helm chart.

3. ArgoCD detects changes in the Helm chart and deploys the new version.

4. Flagger identifies the deployment change and creates a canary deployment while keeping the primary deployment (stable version) running.

5. Istio manages traffic distribution between the primary and canary deployments.

6. Prometheus collects metrics for the canary analysis, which Flagger evaluates:

   - If metrics pass the defined criteria, the canary is promoted to primary, becoming the new stable version.

   - If metrics fail, Flagger automatically rolls back traffic to the primary version.

<p align="center">
    <img src="assets/canary-workflow.jpg" alt="Canary Workflow" width="70%" height="70%">
</p>

### Canary Release Implementation for the Frontend Microservice

To implement the Canary release for the frontend microservice, we defined a Flagger Canary object with the following default configuration:


```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: frontend
  namespace: <release-namespace>
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  progressDeadlineSeconds: 60
  service:
    port: 80
    targetPort: 8080
    portName: http
    gateways:
      - asm-ingress/asm-ingressgateway
    hosts:
      - "*"
  analysis:
    interval: 30s
    threshold: 10
    maxWeight: 25
    stepWeight: 2
    metrics:
    - name: request-success-rate
      threshold: 99
      interval: 30s
    - name: request-duration
      threshold: 500
      interval: 30s
```

The `analysis` section defines the Canary analysis to be performed. In this case, the analysis will:
- Evaluate **request-success-rate**, ensuring at least 99% of requests are successful during the evaluation period.
- Check **request-duration**, ensuring that the average request latency remains below 500ms.

The analysis runs at 30-second intervals and gradually increases traffic to the Canary by `stepWeight` (2%) until it reaches the `maxWeight` (25%). If any threshold is violated, the Canary will be rolled back automatically.

---

#### Testing Successful Canary Promotion

To verify the success of a Canary deployment with a working image change, we made a small change to the frontend source code. Flagger created the Canary deployment as explained earlier. Once the new revision was detected, we observed the Canary's events. The traffic weight increased over time until it reached the maximum weight of 25%, at which point the Canary was promoted:

<p align="center">
    <img src="assets/canary-promotion.jpg" alt="Canary Promotion" width="70%" height="70%">
</p>

We also verified the traffic distribution between the Canary and the primary deployment using the Kiali UI:

<p align="center">
    <img src="assets/kiali-traffic.jpg" alt="Kiali Traffic Distribution" width="70%" height="70%">
</p>

Additionally, we monitored both the Canary and primary deployments using one of the public Grafana dashboards we provisioned:

<p align="center">
    <img src="assets/canary-dashboard.jpg" alt="Istio Canary Grafana Dashboard" width="70%" height="70%">
</p>

---

#### Testing Failed Canary and Automatic Rollback

To test failure handling, we introduced an artificial delay of 3 seconds in the frontend endpoints (except the health check endpoint, so the readiness probe would not fail), the container image of this version of the frontend is `registry.gitlab.com/hamdane10/gke-cloud-project/frontend:v0.10.9`. When Flagger created the Canary deployment, the analysis started, but this time it failed because the request durations exceeded the defined threshold of 500ms. This triggered an automatic rollback:

<p align="center">
    <img src="assets/canary-failed.jpg" alt="Canary Failed" width="70%" height="70%">
</p>

We also configured a Prometheus alert to trigger when Flagger initiates a rollback due to a Canary failure:

<p align="center">
    <img src="assets/canary-rollback-alert.jpg" alt="Canary Rollback Alert" width="70%" height="70%">
</p>

### Key Improvements and Best Practices

The Canary analysis we defined for the frontend works well for testing and demonstration purposes, but there’s still room for improvement to make it more production-ready. Drawing from the recommendations in `The Site Reliability Workbook,` Chapter 16: [Canarying Releases](https://sre.google/workbook/canarying-releases/), we have identified areas where we can improve our canary, as well as what we are already doing well :

#### What We’re Already Doing Well
- **Automated Deployments**: We’ve automated canary releases using Flagger, Istio, and ArgoCD. This setup removes manual errors and makes the whole process more reliable.
- **Traffic Splitting**: Thanks to Istio, we can route specific percentages of traffic to the canary version without worrying about scaling the number of replicas.
- **Automatic Rollbacks**: Flagger is set to roll back automatically if the canary deployment doesn’t meet the defined thresholds, which saves time and avoids downtime.
- **Monitoring and Metrics**: We’ve already got a solid foundation with metrics like request-success-rate and request-duration to evaluate the canary’s performance.
- **Distributed Tracing**: We’re already using OpenTelemetry, Tempo, and Grafana to trace requests across services, giving us valuable insights into performance and bottlenecks.

#### Where We Can Improve
- **More Sophisticated Traffic Routing**: Instead of just splitting traffic evenly, we could use headers-based routing to test specific groups of users,like only routing beta testers or users from certain regions to the canary.

- **Custom Success Criteria**: We should focus on metrics that clearly indicate service problems, starting with SLIs as recommended in the chapter. Our metrics should be carefully selected based on how well they indicate actual user-impacting issues, while avoiding too many metrics which can lead to diminishing returns.

- **Artificial Load Testing**: While synthetic load testing can help with code coverage, we should be cautious about relying solely on it. As the chapter points out, artificial load may not accurately model organic traffic patterns or state coverage, especially in mutable systems (those with caches, cookies, request affinity). Additionally, some scenarios like billing systems could be dangerous to test with artificial load.

- **Mixing with Blue/Green Deployments**: For high-risk updates, combining canary releases with blue/green deployments would give us a fallback plan. This way, we’d always have a fully functional previous version running in parallel.

- **Smarter Alerts**: Right now, our alerts are static, but we could make them adaptive to account for baseline changes during canary analysis. This would cut down on unnecessary alerts.

- **Gradual Canary Evaluation**: We can implement a multi-stage canary process where initial stages use a smaller population to minimize negative impact and focus on clear problem indicators (like application crashes and request failures). After successfully passing these initial stages, we can then move to larger populations for more comprehensive analysis, as recommended in the chapter's `Use a Gradual Canary for Better Metric Selection` section.

- **Post-Promotion Validation**: Once the canary is promoted, running automated end-to-end tests could help ensure the new version works smoothly across the entire system.

By addressing these areas, we can take our canary release process to the next level, making it even more reliable and efficient in a production environment.

## Implementing a Logging Solution for the Online Boutique Application

For the logging part, we decided to take a different approach than what was suggested in the assignment. Instead of implementing a dedicated OrderLog microservice with a storage backend, we deployed a logging system composed of:

- **OpenTelemetry Collector** for log collection
- **Loki**, an open-source log aggregation system that indexes metadata rather than log contents, making it cost-effective and efficient
- **Grafana** for log visualization and analysis

Since we deployed a robust logging system, we decided not only to store order logs but also to modify the source code of each microservice by adding a new component called `Business Logger.` This component exposes business-related logs. These modifications were made easier by the CI/CD pipelines we set up at the beginning of the project. These pipelines automatically build new container images and Helm charts after committing modifications. Below are the details of the business logs added to each microservice:

| Service | Business Logs Exposed |
|---------------------|----------------------|
| Frontend | • **Checkout Conversion Rate**: Percentage of completed checkouts vs started checkouts (calculated as `checkoutComplete/checkoutStarts * 100`)<br>• **Total Checkouts**: Number of completed checkout operations<br>• **Total Cart Views**: Number of times users started the checkout process<br>• **Product Views**: Tracks views per product ID<br>• **Order Value by Currency**: Total order values grouped by currency<br>• **Currency Preferences**: Number of times each currency was selected by users |
| CartService | • **Cart Statistics (Every 5 minutes)**:<br>&nbsp;&nbsp;- Total cart views count<br>&nbsp;&nbsp;- Total add-to-cart operations count<br>&nbsp;&nbsp;- Total empty cart operations count<br>&nbsp;&nbsp;- Number of unique users<br>&nbsp;&nbsp;- Total items added<br>&nbsp;&nbsp;- Top 5 products added to carts<br>• **Individual Events**:<br>&nbsp;&nbsp;- Large cart views (carts with >10 items)<br>&nbsp;&nbsp;- Large quantity additions (>5 items at once)<br>&nbsp;&nbsp;- Cart operation errors with details |
| ProductCatalogService | • **Product Views Summary (Every 5 minutes)**:<br>&nbsp;&nbsp;- Total view count<br>&nbsp;&nbsp;- Number of unique products viewed<br>&nbsp;&nbsp;- Top 5 most viewed products<br>• **Search Analytics**:<br>&nbsp;&nbsp;- Search queries performed<br>&nbsp;&nbsp;- Number of results per search<br>&nbsp;&nbsp;- Search latency in milliseconds<br>• **Catalog Operations**:<br>&nbsp;&nbsp;- Catalog reload events<br>&nbsp;&nbsp;- Product count after operations<br>&nbsp;&nbsp;- Operation status (success/error)<br>• **Error Events**:<br>&nbsp;&nbsp;- Product not found incidents |
| CurrencyService | • **Currency Conversion Metrics (Every 1 minute)**:<br>&nbsp;&nbsp;- Total number of conversions performed<br>&nbsp;&nbsp;- Top 5 most used currency pairs (e.g., "USD->EUR")<br>&nbsp;&nbsp;- Conversion patterns and trends |
| PaymentService | • **Individual Transaction Logs**:<br>&nbsp;&nbsp;- Transaction ID<br>&nbsp;&nbsp;- Transaction status (success/failed)<br>&nbsp;&nbsp;- Amount and currency<br>&nbsp;&nbsp;- Card type and last four digits<br>&nbsp;&nbsp;- Failure reason (if applicable)<br>• **Health Metrics (Every 5 minutes)**:<br>&nbsp;&nbsp;- Total transaction count<br>&nbsp;&nbsp;- Success rate percentage<br>&nbsp;&nbsp;- Failure count |
| ShippingService | • **Shipping Statistics (Every 100 events or 5 minutes)**:<br>&nbsp;&nbsp;- Number of quote requests<br>&nbsp;&nbsp;- Number of shipping orders created<br>&nbsp;&nbsp;- Total quote amount in USD<br>&nbsp;&nbsp;- Shipping requests by region<br>• **Individual Order Events**:<br>&nbsp;&nbsp;- Successful shipping order creation with tracking ID<br>&nbsp;&nbsp;- Quote generation errors<br>&nbsp;&nbsp;- Shipping order creation errors |
| EmailService | • **Email Statistics (Every 50 events or 5 minutes)**:<br>&nbsp;&nbsp;- Number of emails successfully sent<br>&nbsp;&nbsp;- Number of failed email attempts<br>&nbsp;&nbsp;- Number of template rendering errors<br>&nbsp;&nbsp;- Email distribution by domain<br>• **Error Events**:<br>&nbsp;&nbsp;- Individual email sending failures<br>&nbsp;&nbsp;- Template rendering failures |
| CheckoutService | • **Order Statistics (Every 5 minutes)**:<br>&nbsp;&nbsp;- Total order count<br>&nbsp;&nbsp;- Success and failure counts<br>&nbsp;&nbsp;- Total order amount<br>&nbsp;&nbsp;- Currency distribution<br>• **Individual Order Events**:<br>&nbsp;&nbsp;- Complete order details (order ID, user ID, amount, items, etc.)<br>• **Error Events**:<br>&nbsp;&nbsp;- Cart preparation failures<br>&nbsp;&nbsp;- Payment processing failures<br>&nbsp;&nbsp;- Shipping failures<br>&nbsp;&nbsp;- Cart emptying failures<br>&nbsp;&nbsp;- Email confirmation failures |
| RecommendationService | • **Recommendation Statistics (Every 20 requests or 1 minute)**:<br>&nbsp;&nbsp;- Total recommendation requests<br>&nbsp;&nbsp;- Total recommendations made<br>&nbsp;&nbsp;- Top 5 most recommended products<br>• **Processing Details**:<br>&nbsp;&nbsp;- Asynchronous processing via queue<br>&nbsp;&nbsp;- Background thread for log processing<br>• **Error Events**:<br>&nbsp;&nbsp;- Recommendation generation errors<br>&nbsp;&nbsp;- Processing and queuing errors |
| AdService | • **Ad Performance Metrics (Every 5 minutes)**:<br>&nbsp;&nbsp;- Ad serve count by category<br>&nbsp;&nbsp;- Top 5 most used context keys<br>&nbsp;&nbsp;- Individual ad request logs with context keys<br>• **Error Reports**:<br>&nbsp;&nbsp;- Error counts by type<br>&nbsp;&nbsp;- Detailed error messages and types |

Some of the logs we've implemented aggregate data over a period of time. For example, order statistics every 5 minutes display total order counts. While we acknowledge that processing and calculating data over time can be resource-intensive, and ideally such aggregations should be done at the backend logging level (Loki in our case), we chose to implement this at the application level. This decision helps reduce the amount of logs generated, minimizing storage usage and keeping costs low, especially since we are using a Google Cloud bucket for log persistence.

### How Our System Works

1. **Logs Collection**
    We used the same OpenTelemetry setup for tracing to collect logs. However, when logging is enabled, OpenTelemetry is deployed as a **DaemonSet** instead of a **Deployment**. A DaemonSet ensures that a replica of the pod runs on every cluster node. This setup allows us to collect logs from all application pods distributed across different nodes. To collect these logs, we mounted a volume at the path where pod logs are stored: `/var/log/pods/*`.

    <p align="center">
        <img src="assets/opentelemetrycollector-logs.jpg" alt="OpenTelemetry Collector Logs" width="70%" height="70%">
    </p>

2. **Logs Storage**
    OpenTelemetry pushes the collected logs to Loki's write component. Loki supports various cloud-based object storage solutions, such as Google Cloud Storage, for their scalability and durability. Using Terraform, we automated the creation of a storage bucket called [`loki-storage-tsdb-24`](terraform/gcs-logging-bucket.tf). We also enabled **Workload Identity**, a recommended approach to securely access Google Cloud services without managing service account keys. This allows Loki to access the storage bucket securely. After receiving logs, Loki temporarily stores them in a local persistent volume before uploading them to the bucket. We defined a retention policy of 7 days for the data stored in the bucket, which can be adjusted based on needs.

    <p align="center">
        <img src="assets/loki-logging.jpg" alt="Logs Storage System" width="70%" height="70%">
    </p>

3. **Logs Visualization and Analysis**
    To visualize logs, we automated the creation of a data source for Loki and provisioned a public dashboard for visualizing Loki logs. This was achieved by passing the necessary configurations during the installation of the kube-prometheus-stack with Helm. Below is an example of the `order_completed` events from the checkout microservice:

    <p align="center">
        <img src="assets/loki-grafana-dashboard.jpg" alt="Logs Visualization" width="70%" height="70%">
    </p>

### Comparison Between Suggested Approach and Our Approach

1. **Suggested Approach: OrderLog with a Storage Backend**

    In this design, an OrderLog microservice acts as a stateless entry point and forwards logs to a stateful storage backend, such as a database.

    **Pros**:
    - Simple design that abstracts storage complexity.
    - Supports flexible and mature database solutions like MySQL or Redis.
    - Clear separation of concerns between logging and storage layers.

    **Cons**:
    - Higher costs due to database management and scaling.
    - Can become a scalability bottleneck under heavy log workloads.
    - Additional latency introduced by the microservice and database layers.

2. **Our Approach: Loki as the Logging System**

    We directly integrated Loki as the logging system, using OpenTelemetry for log collection and storing logs in scalable cloud object storage.

    **Pros**:
    - Cost-effective due to metadata indexing and object storage.
    - Natively integrates with Kubernetes and visualization tools like Grafana.
    - Optimized for log aggregation and querying in cloud-native setups.

    **Cons**:
    - Steeper learning curve for configuration and setup.
    - Limited to log-specific use cases, with fewer complex querying options.

#### **Conclusion**
The suggested approach is suitable for scenarios needing database-level querying or integration with application workflows. Our Loki-based approach better supports large-scale, cloud-native applications by providing scalability, cost efficiency, and seamless integration.

### Why Deploying Loki in GKE

We chose to deploy Loki in GKE rather than on a GCE virtual machine for the following key reasons:

1. **Simplified Management**: GKE automates tasks like scaling, updates, and health monitoring, which would require significant manual effort on a GCE VM.

2. **Resource Efficiency**: Kubernetes' dynamic resource allocation and autoscaling in GKE ensure efficient use of resources, unlike the fixed capacity of a GCE VM.

3. **Scalability Challenges in GCE**: Managing horizontal scaling, redundancy, and load balancing for Loki in GCE would be complex and time-consuming compared to GKE’s built-in capabilities.

Deploying Loki in GKE provides operational efficiency and flexibility while avoiding the complexity of managing stateful workloads on a GCE VM.

### Managing Loki System in GKE
Loki is deployed in our GKE cluster using Helm. The default Loki installation includes many features (e.g., caching, canary) and deploys components with large resource requests, limits, and replicas. This configuration makes Loki resource-intensive. To adapt Loki to our setup, we used a custom values file when installing Loki with Helm, configuring it to deploy only four components with adjusted resource requests, limits, and replica counts. These components are divided into two Kubernetes object kinds:

- **Deployments**:
  - **loki-gateway**: Acts as the entry point for queries and log writes, routing requests to the appropriate Loki components.
  - **loki-read**: Handles read queries, fetching logs stored in the backend.

- **StatefulSets**:
  - **loki-backend**: Stores log data persistently and interfaces with the cloud storage bucket.
  - **loki-write**: Manages log ingestion and forwards data to the backend for storage.

The key difference between Deployments and StatefulSets lies in their handling of state. Deployments are stateless, making them suitable for components like `loki-gateway` and `loki-read`, which do not require persistent storage. On the other hand, StatefulSets are used for components like `loki-backend` and `loki-write`, as they require persistent storage and stable pod identities to ensure data consistency.

### Key Improvements for Managing Loki under Heavy Load

We initially deployed Loki in our GKE cluster with a configuration adapted to our setup. However, if we want to deploy loki to handle heavy loads effectively, one significant improvement is to create a separate node pool in the GKE cluster dedicated exclusively to Loki workloads. This approach ensures that Loki's resource-intensive processes do not compete with application workloads for CPU or memory.

The node pool can be created using Terraform, and cluster autoscaling can be enabled for this Loki-specific node group. To isolate these nodes, taints can be applied to the nodes, such as `loki-workload-nodes`. A taint ensures that only pods with specific tolerations can be scheduled on these nodes. After creating the node pool with the taint and enabling autoscaling if necessary, tolerations need to be added to the Loki deployment configuration to ensure that Loki workloads are deployed to the dedicated nodes.


<p align="center">
    <img src="assets/loki-tolerations.jpg" alt="Loki dedicated node pool " width="70%" height="70%">
</p>

## Deploying a Self-Managed Kubernetes Cluster with Custom Autoscaler

We have prior experience deploying self-managed Kubernetes clusters using **kubeadm** in Google Cloud. As double-degree students, last year during the third year of the ISI program, we had the opportunity to work on deploying a Kubernetes cluster for the `SDTD` course (*Systèmes distribués pour le traitement des données*) under the supervision of **Thomas Ropars**. The project code is publicly available in two GitHub repositories: one for the [application code](https://github.com/Hamdane-yassine/weather-forecast) and another for [the infrastructure configuration](https://github.com/Hamdane-yassine/weather-forecast-infra-repo). 

### Accomplishments from Last Year's Project
In our previous project, we successfully achieved the following :
- **Self-Managed Kubernetes Deployment**: We deployed a Kubernetes cluster at the IaaS level using **Terraform**, **Ansible**, and **kubeadm** for cluster provisioning.
- **Configurable Cluster Setup**: The cluster could be deployed with a configurable number of master and worker nodes. For clusters with multiple master nodes, we implemented **HAProxy** as a load balancer. This load balancer was deployed on a separate virtual machine, serving as the single entry point to the infrastructure and application. It also acted as an external gateway to route user requests to the application within the cluster.

### Limitations of the Previous Infrastructure
One of the main limitations of the previous setup was the lack of a **cluster autoscaler** :
- The number of worker nodes remained static after deployment.
- **Scalability Issues**: A small number of worker nodes could not handle high user loads effectively, leading to performance bottlenecks.
- **Resource Wastage**: Deploying a large number of workers to handle potential peak loads resulted in unused resources during periods of low activity, making it cost-inefficient.

### Improving on the Previous Work
For this project, we aimed to address the limitations of our previous work by designing and implementing a **custom cluster autoscaler** for a self-managed Kubernetes cluster. This improvement allows the cluster to dynamically adjust the number of worker nodes based on workload demands, optimizing both performance and cost-efficiency.

The code related to the autoscaler is available in another public gitlab repository.

### Designing the custom cluster autoscaler

1. **First Approach**: Monitor scheduling events and use alerts to trigger scale out and down operations

    <p align="center">
        <img src="assets/autoscaling-alert.jpg" alt="Custom autoscaler design using alerts " width="90%" height="90%">
    </p>

    The architecture implements autoscaling through a monitoring-based approach:

    **Scale Out Process:**
    - Prometheus continuously monitors pod scheduling events in the cluster
    - When pods fail to schedule due to insufficient resources, an AlertManager rule is triggered
    - The alert notification is sent to an SMTP server or Slack
    - This notification automatically triggers a predefined GitLab pipeline
    - The pipeline executes the scale-out task, which provisions and joins a new worker node to the cluster

    **Scale Down Process:**
    - Node utilization metrics are monitored by Prometheus (CPU, memory, etc.)
    - When a node remains underutilized for a specified period, an alert is triggered
    - The scale-down pipeline is activated, which:
      1. Cordons the target node to prevent new pod scheduling
      2. Safely drains existing pods to other nodes
      3. Waits for successful pod migration
      4. Removes the node from both Kubernetes and the underlying infrastructure

    **Main Limitations:**

    1. **Reactive Nature:** The system only responds after scheduling failures occur, leading to potential service degradation during scaling operations.

    2. **Scale Down Risks:** Complex node selection process and potential service disruption during pod migration.

    3. **Alert Management:** Risk of alert fatigue and race conditions when multiple scaling events occur simultaneously.

    4. **Limited Intelligence:** No predictive scaling capabilities or optimization strategies for different workload patterns.

    5. **High Maintenance:** Multiple components and pipelines require continuous monitoring and adjustment.

2. **Second Approach:** Leveraging Kubernetes Cluster Autoscaler with External gRPC Provider

    This approach utilizes the [Kubernetes Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) open-source project with its [External gRPC Provider](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/cloudprovider/externalgrpc) interface to implement custom scaling logic.

    <p align="center">
        <img src="assets/autoscaler-project.jpg" alt="K8s Autoscaler with External gRPC Architecture" width="90%" height="90%">
    </p>

    The architecture implements autoscaling by integrating the official Kubernetes Cluster Autoscaler with a custom cloud provider through gRPC:

    **Components Overview:**
    - Kubernetes Cluster Autoscaler running with external gRPC provider enabled
    - Custom Cloud Provider implementing the gRPC server interface
    - GitLab pipeline integration for actual node provisioning and cleanup

    <p align="center">
        <img src="assets/autoscaler-diagram.jpg" alt="Scaling Operation Sequence" width="90%" height="90%">
    </p>

    **Scale Out Process:**
    - Cluster Autoscaler detects unschedulable pods automatically
    - External gRPC client (part of autoscaler) makes scaling requests
    - Custom provider receives the request through gRPC interface
    - Provider triggers GitLab pipeline for node provisioning
    - New node joins the cluster through kubeadm

    **Scale Down Process:**
    - Cluster Autoscaler identifies underutilized nodes using built-in algorithms
    - Scale down request is sent through gRPC to custom provider
    - Provider initiates pipeline for safe node removal
    - Pipeline handles node draining and cleanup
    - Node is removed from both cluster and infrastructure

    **Main Limitations:**

    1. **Implementation Complexity:** Requires development and maintenance of a custom gRPC server implementing the CloudProvider interface.

    2. **Pipeline Integration:** Need to carefully handle communication between gRPC server and GitLab pipelines to ensure reliability.

    3. **State Management:** Must maintain consistent state between Cluster Autoscaler, gRPC server, and actual infrastructure.

    4. **Recovery Handling:** Additional complexity in handling failures during scaling operations and ensuring proper recovery.

    5. **Version Compatibility:** Need to maintain compatibility with Cluster Autoscaler's gRPC interface across versions.

### Comparing Both Approaches

While both designs have their limitations, here's why the second approach using Kubernetes Cluster Autoscaler is more advantageous:

**Key Differences:**

1. **Scaling Intelligence:**
  - First Approach: Simple threshold-based decisions using alerts
  - Second Approach: Leverages battle-tested K8s Autoscaler algorithms

2. **Implementation Complexity:**
  - First Approach: Requires building scaling logic from scratch
  - Second Approach: Only needs gRPC server implementation

3. **Maintenance Burden:**
  - First Approach: Must maintain alert rules and custom scaling logic
  - Second Approach: Benefits from K8s community updates and improvements

**Why Second Approach is Better:**

1. **Reduced Development Effort:** No need to handle complex node selection and pod scheduling logic

2. **Better Scaling Decisions:** Uses proven algorithms for node selection and respects pod constraints

3. **Future Proofing:** Benefits from continuous community improvements and better K8s ecosystem compatibility

### Implementing the second approach:

In the [autoscaler repository](https://gitlab.com/Hamdane10/autoscaler-project), there is the code related to provisioning the cluster from our project last year, as well as the newly added components to manage cluster autoscaling. These components are described below:

#### 1. [**ip-manager.sh**](https://gitlab.com/Hamdane10/autoscaler-project/-/blob/27a9a608d9df3d5d0dded564df174dab2bc04c7a/scripts/ip-manager.sh)
   - **Purpose:** Manages IP pool initialization, assignment, and release for worker and master nodes.
   - **Key Features:** Handles IP availability, updates Terraform configurations, and maintains consistency between infrastructure and Kubernetes state.

#### 2. [**worker-playbook.yaml**](https://gitlab.com/Hamdane10/autoscaler-project/-/blob/27a9a608d9df3d5d0dded564df174dab2bc04c7a/configuration/worker-playbook.yaml)
   - **Purpose:** Automates the configuration and integration of worker nodes into the Kubernetes cluster.
   - **Key Features:** 
     - Loads cluster join details (e.g., tokens, CA certificates).
     - Executes the `kubeadm join` command to register worker nodes.

#### 3. [**remove-node.yaml**](https://gitlab.com/Hamdane10/autoscaler-project/-/blob/27a9a608d9df3d5d0dded564df174dab2bc04c7a/configuration/remove-node.yaml)
   - **Purpose:** Safely removes nodes from the Kubernetes cluster.
   - **Key Features:**
     - Verifies node existence.
     - Executes cordon and drain operations.
     - Deletes the node from Kubernetes and verifies its removal.

#### 4. [**scale-out.sh**](https://gitlab.com/Hamdane10/autoscaler-project/-/blob/27a9a608d9df3d5d0dded564df174dab2bc04c7a/scale-out.sh)
   - **Purpose:** Handles scaling out by provisioning new worker nodes and integrating them into the cluster.
   - **Key Features:**
     - Updates worker node count in environment variables.
     - Assigns new IPs and provisions infrastructure using Terraform.
     - Configures new workers with necessary tools and Kubernetes setup.

#### 5. [**scale-down.sh**](https://gitlab.com/Hamdane10/autoscaler-project/-/blob/27a9a608d9df3d5d0dded564df174dab2bc04c7a/scale-down.sh)
   - **Purpose:** Manages scaling down by removing underutilized worker nodes.
   - **Key Features:**
     - Identifies and releases resources for specified nodes.
     - Updates HAProxy configurations and regenerates IP pools.

#### 6. [**.gitlab-ci.yml**](https://gitlab.com/Hamdane10/autoscaler-project/-/blob/27a9a608d9df3d5d0dded564df174dab2bc04c7a/.gitlab-ci.yml)
   - **Purpose:** Defines the CI/CD pipelines for deploying, scaling, and maintaining the Kubernetes cluster.
   - **Key Features:**
     - Automates scale-out and scale-down tasks.
     - Ensures state consistency through GitLab pipelines.
     - Integrates with Terraform for infrastructure management.

We successfully tested the GitLab pipelines for scaling out and down by triggering them manually. Additionally, we deployed the Kubernetes autoscaler. However, due to time constraints, we were unable to complete the development of the custom gRPC server, which is intended to trigger the GitLab pipelines upon receiving requests from the autoscaler.