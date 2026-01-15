1. Span Object Replacement
Lightweight CKSpan instead of full OpenTelemetry spans
Minimal data storage (no events, links, full trace context)
2. Span Processing Pipeline
Noop span processors/exporters (suppress default OpenTelemetry export)
Custom CKGraphSpanProcessor for graph path conversion
No standard span export
3. Metrics-First Architecture
Emit metrics instead of exporting spans
Custom metric types (latency percentiles, throughput, errors)
HDRHistogram for percentile calculations
4. Context Propagation System
Custom ck-route propagator instead of standard trace context
Graph path hash propagation across services
Custom header/property injection
5. Graph Path Building
Convert spans to Graph Path Elements (GPE)
Build domain graphs from trace data
Path key generation and management
6. Instrumenter Modification
Modified Instrumenter in bootstrap classloader
Custom span creation logic (doCKStartImpl, doCKEnd)
Bypass standard OpenTelemetry span lifecycle
7. Custom Library Instrumentations
ByteBuddy-based custom instrumentations
Library-specific code injection (Spring, AWS, Kafka, etc.)
Override/extension of OSS OpenTelemetry instrumentations
8. Configuration & Auto-Configuration
Disabled default OpenTelemetry exporters
Custom auto-configuration provider
Conditional metric collection
9. Method Intelligence Layer
Application-wide method tracking
Call stack building
CPU profiling integration
10. Build & Packaging
Bootstrap classloader modifications
Class relocation/shading
Multi-release JAR structure
Selective exclusion of upstream classes
These are the main areas where ck-agent diverges from standard OpenTelemetry.