# Tailnet-wide resources belong here; host daemon settings stay with each host.
_: {
  terraform = {
    required_version = ">= 1.10.0";
    required_providers.tailscale = {
      source = "tailscale/tailscale";
      version = "= 0.30.0";
    };
    # State and saved plans contain generated credentials. Never allow plaintext.
    encryption = {
      key_provider.pbkdf2.state.passphrase = "\${var.state_passphrase}";
      method.aes_gcm.state.keys = "\${key_provider.pbkdf2.state}";
      state = {
        method = "method.aes_gcm.state";
        enforced = true;
      };
      plan = {
        method = "method.aes_gcm.state";
        enforced = true;
      };
    };
  };
  provider.tailscale = {};

  variable = {
    state_passphrase = {
      type = "string";
      sensitive = true;
      description = "State encryption passphrase supplied at runtime; retain it for recovery.";
      validation = {
        condition = "\${length(var.state_passphrase) >= 32}";
        error_message = "Use a persistent state encryption passphrase of at least 32 characters.";
      };
    };
    base_policy = {
      type = "string";
      description = "Reviewed JSON export of the existing full tailnet policy; no empty default.";
      validation = {
        condition = "\${can(keys(jsondecode(var.base_policy)))}";
        error_message = "base_policy must be a JSON object exported from the existing tailnet.";
      };
    };
    enable_t1_enrollment = {
      type = "bool";
      default = false;
      description = "Create a fresh single-use key only when enrolling or re-enrolling T1.";
    };
    enable_lan_dns = {
      type = "bool";
      default = false;
      description = "Opt in to .lan split DNS after checking existing resolver ownership.";
    };
    enable_t3_enrollment = {
      type = "bool";
      default = false;
      description = "Create a fresh single-use key only when enrolling or re-enrolling T3.";
    };
  };

  locals = {
    baseline = "\${jsondecode(var.base_policy)}";
    tag_owners = {
      "tag:ci" = "\${distinct(concat(try(local.baseline.tagOwners[\"tag:ci\"], []), [\"autogroup:admin\"]))}";
      "tag:homelab-router" = ["autogroup:admin"];
      "tag:homelab-t3" = ["autogroup:admin"];
    };
    route_approvers = {
      "192.168.2.0/24" = "\${distinct(concat(try(local.baseline.autoApprovers.routes[\"192.168.2.0/24\"], []), [\"tag:homelab-router\"]))}";
    };
    cache_grants = [
      {
        src = ["tag:ci"];
        dst = ["192.168.2.8"];
        ip = ["tcp:8080"];
      }
    ];
    ci_tests = [
      {
        src = "tag:ci";
        accept = ["192.168.2.8:8080"];
        deny = ["192.168.2.8:22" "192.168.2.3:22" "192.168.2.1:80"];
      }
    ];
    routes = "\${merge(try(local.baseline.autoApprovers.routes, {}), local.route_approvers)}";
    managed_policy = {
      tagOwners = "\${merge(try(local.baseline.tagOwners, {}), local.tag_owners)}";
      autoApprovers = "\${merge(try(local.baseline.autoApprovers, {}), { routes = local.routes })}";
      grants = "\${concat(try(local.baseline.grants, []), local.cache_grants)}";
      tests = "\${concat(try(local.baseline.tests, []), local.ci_tests)}";
    };
    policy = "\${merge(local.baseline, local.managed_policy)}";
  };

  # Adoption imports the existing policy. Never bypass its overwrite safeguard.
  import = [
    {
      to = "tailscale_acl.personal";
      id = "acl";
    }
  ];
  resource = {
    tailscale_acl.personal = {
      acl = "\${jsonencode(local.policy)}";
      lifecycle.prevent_destroy = true;
    };
    tailscale_oauth_client.ci = {
      description = "infra nixCfg CI";
      scopes = ["auth_keys"];
      tags = ["tag:ci"];
      depends_on = ["tailscale_acl.personal"];
    };
    tailscale_tailnet_key.t1 = {
      count = "\${var.enable_t1_enrollment ? 1 : 0}";
      description = "T1 subnet router";
      reusable = false;
      ephemeral = false;
      preauthorized = true;
      expiry = 3600;
      recreate_if_invalid = "never";
      tags = ["tag:homelab-router"];
      depends_on = ["tailscale_acl.personal"];
    };
    tailscale_dns_split_nameservers.lan = {
      count = "\${var.enable_lan_dns ? 1 : 0}";
      domain = "lan";
      nameservers = ["192.168.2.1"];
    };
    tailscale_tailnet_key.t3 = {
      count = "\${var.enable_t3_enrollment ? 1 : 0}";
      description = "T3 services host";
      reusable = false;
      ephemeral = false;
      preauthorized = true;
      expiry = 3600;
      recreate_if_invalid = "never";
      tags = ["tag:homelab-t3"];
      depends_on = ["tailscale_acl.personal"];
    };
  };
  output = {
    ci_client_id = {
      value = "\${tailscale_oauth_client.ci.id}";
      sensitive = true;
    };
    ci_client_secret = {
      value = "\${tailscale_oauth_client.ci.key}";
      sensitive = true;
    };
    t1_auth_key = {
      value = "\${try(tailscale_tailnet_key.t1[0].key, null)}";
      sensitive = true;
    };
    t3_auth_key = {
      value = "\${try(tailscale_tailnet_key.t3[0].key, null)}";
      sensitive = true;
    };
  };
}
