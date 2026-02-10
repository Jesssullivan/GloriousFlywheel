%{ if mode == "passthrough" ~}
# Passthrough mode — simple reverse proxy
:${port} {
  reverse_proxy localhost:${backend_port}
}
%{ endif ~}

%{ if mode == "mtls_only" ~}
# mTLS mode — require client certificate
:${port} {
  tls {
    client_auth {
      mode ${mtls_client_auth_mode}
      trust_pool file /etc/caddy/mtls/ca.pem
    }
  }

  header_up X-Client-Cert-CN {tls_client_subject}
  header_up X-Client-Cert-Fingerprint {tls_client_fingerprint}
  header_up X-Webauth-User {tls_client_subject}

  reverse_proxy localhost:${backend_port}
}
%{ endif ~}

%{ if mode == "tailscale_only" ~}
# Tailscale mode — bind to Tailscale network only
{
  tailscale {
    auth_key {env.TS_AUTHKEY}
  }
}

:${port} {
  bind tailscale/${tailscale_hostname}

  @tailscale_auth {
    remote_ip 100.64.0.0/10
  }

  header_up X-Webauth-User {http.auth.user.tailscale_user}
  header_up X-Webauth-Email {http.auth.user.tailscale_user}

  reverse_proxy localhost:${backend_port}
}
%{ endif ~}

%{ if mode == "mtls_and_tailscale" ~}
# Combined mTLS + Tailscale mode
{
  tailscale {
    auth_key {env.TS_AUTHKEY}
  }
}

:${port} {
  bind tailscale/${tailscale_hostname}

  tls {
    client_auth {
      mode ${mtls_client_auth_mode}
      trust_pool file /etc/caddy/mtls/ca.pem
    }
  }

  header_up X-Client-Cert-CN {tls_client_subject}
  header_up X-Client-Cert-Fingerprint {tls_client_fingerprint}
  header_up X-Webauth-User {tls_client_subject}
  header_up X-Webauth-Email {http.auth.user.tailscale_user}

  reverse_proxy localhost:${backend_port}
}
%{ endif ~}
