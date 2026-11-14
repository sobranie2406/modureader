These CA/localhost certificates and localhost key are public test fixtures.
They are used only by loopback TLS tests and must never be used by a deployed service.

The leaf has an 825-day validity period to satisfy Apple's TLS policy. Renew it
before February 2029. Tests trust this CA only within the network test isolate;
production connections always use the platform's normal certificate authorities.
