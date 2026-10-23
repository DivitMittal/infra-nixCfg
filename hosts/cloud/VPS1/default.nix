_: {
  terraform.required_providers.ovh = {
    source = "ovh/ovh";
    version = "~> 2.15";
  };

  # Generate an application key/secret at https://eu.api.ovh.com/createApp/,
  # then a consumer key scoped to that pair via OVH's token-creation
  # wizard/API — Terraform cannot mint a consumer key itself.
  variable.ovh_application_key = {
    type = "string";
    sensitive = true;
    description = "OVH API application key (infra-nixCfg-secrets: secrets/cloud/ovh-application-key.age)";
  };
  variable.ovh_application_secret = {
    type = "string";
    sensitive = true;
    description = "OVH API application secret (infra-nixCfg-secrets: secrets/cloud/ovh-application-secret.age)";
  };
  variable.ovh_consumer_key = {
    type = "string";
    sensitive = true;
    description = "OVH API consumer key scoped to the application key/secret pair above (infra-nixCfg-secrets: secrets/cloud/ovh-consumer-key.age)";
  };

  # No "IN" OVH subsidiary/endpoint exists (confirmed against the live
  # OVH order/catalog API: ovhSubsidiary is one of
  # CZ/DE/ES/EU/FI/FR/GB/IE/IT/LT/MA/NL/PL/PT/SN/TN — India is served out of
  # the Mumbai ("YNM") datacenter but billed through one of these entities).
  # Set this to whatever subsidiary your actual OVH account is registered
  # under (visible in the OVH control panel, or `GET /me` once authenticated).
  # "IE" is confirmed to expose the YNM datacenter for the plan below, but
  # your account's billing subsidiary may differ.
  variable.ovh_subsidiary = {
    type = "string";
    description = "OVH account subsidiary, e.g. \"IE\" — see https://eu.api.ovh.com/console/#/me GET, or the OVH control panel";
  };

  provider.ovh = {
    # "ovh-eu" is correct even though this VPS lives in OVH's Mumbai
    # datacenter — OVH has no separate India API endpoint.
    endpoint = "ovh-eu";
    application_key = "\${var.ovh_application_key}";
    application_secret = "\${var.ovh_application_secret}";
    consumer_key = "\${var.ovh_consumer_key}";
  };

  # Replaces the decommissioned datalix VPS (formerly hosts/nixos/VPS2).
  # Commissions the box only — no public_ssh_key/image_id here, since setting
  # public_ssh_key at creation requires image_id and terraform-provider-ovh's
  # own issue tracker (ovh/terraform-provider-ovh#1198, #1229) flags that
  # pairing as unreliable. OS install instead goes through the same path as
  # VPS0/VPS1: `bootstrap-remote` + nixos-anywhere over SSH against the
  # rescue/default image, using the root password OVH emails on creation
  # (see hosts/README.md "Remote NixOS Bootstrap").
  resource.ovh_vps.C1 = {
    display_name = "VPS1";
    ovh_subsidiary = "\${var.ovh_subsidiary}";
    plan = [
      {
        duration = "P1M";
        # vps-2025-model1: 4 vCore / 8 GiB RAM / 75 GB NVMe, ~EUR6.49/mo at
        # "default" (no upfront commitment) pricing — the cheapest
        # current-generation plan confirmed (via the live OVH catalog API)
        # to offer the YNM (Mumbai) datacenter. vps-2025-model2/3/... step up
        # from there. Re-verify plan_code against the catalog API before
        # changing it — OVH revises this list over time:
        #   curl 'https://api.ovh.com/1.0/order/catalog/public/vps?ovhSubsidiary=IE'
        plan_code = "vps-2025-model1";
        pricing_mode = "default";
        configuration = [
          {
            label = "vps_datacenter";
            value = "YNM"; # Mumbai
          }
          {
            label = "vps_os";
            value = "Debian 12";
          }
        ];
      }
    ];
  };
}
