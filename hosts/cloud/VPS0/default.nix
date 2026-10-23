_: {
  terraform.required_providers.oci = {
    source = "oracle/oci";
    version = "~> 7.0";
  };

  # Permanent API-key auth (not a session token — those expire hourly and
  # made unattended/retry-loop provisioning impractical during VPS0's
  # 2026-08-18/21 re-provisioning). oci_private_key_path is decrypted to a
  # runtime-only temp file by flake/terranix.nix's cloud-VPS0 app (from
  # infra-nixCfg-secrets' cloud/oci-api-key.age), the same way VPS1's OVH
  # credentials are handled. private_key_path (a real file) is used
  # instead of the inline private_key string — passing the decrypted PEM
  # inline via TF_VAR (captured through shell `$()`, which strips the
  # trailing newline) hit "Failed to verify the HTTP(S) Signature" even
  # though the exact same key content authenticated fine via `oci` CLI's
  # --key-file against a real file. The public half is uploaded to the OCI
  # user via `oci iam user api-key upload`; oci_fingerprint is that key's
  # fingerprint.
  # Below: static account/network facts for this tenancy (single tenancy,
  # single user, single AD, single VCN/subnet — confirmed via `oci iam
  # user/availability-domain/compartment list` and `oci network subnet
  # list` on 2026-08-21). These are identifiers, not credentials — nothing
  # here can authenticate on its own — so they're plain defaults rather
  # than agenix secrets, same as oci_ssh_public_key below. Only the API
  # signing key (oci_private_key_path) is sensitive.
  variable.oci_tenancy_ocid = {
    type = "string";
    default = "ocid1.tenancy.oc1..aaaaaaaadfxltq446p457dd4swuvahfvctxw7jyghysmn7u2er2ikvnmtxxa";
  };
  variable.oci_user_ocid = {
    type = "string";
    default = "ocid1.user.oc1..aaaaaaaa5yvfn7td5g2ydr3rju3dnqaer4p6tzfafdetygklleqk3evcwlvq";
  };
  # Fingerprint of the active API key already uploaded via `oci iam user
  # api-key upload`; must match the public half of oci-api-key.age.
  variable.oci_fingerprint = {
    type = "string";
    default = "d3:8a:b8:a2:6d:f5:d7:b1:8e:7b:4f:19:b5:41:82:49";
  };
  variable.oci_private_key_path = {
    type = "string";
    sensitive = true;
  };
  variable.oci_region = {
    type = "string";
    default = "ap-mumbai-1";
  };
  # Root compartment (tenancy) — this tenancy has no sub-compartments.
  variable.oci_compartment_ocid = {
    type = "string";
    default = "ocid1.tenancy.oc1..aaaaaaaadfxltq446p457dd4swuvahfvctxw7jyghysmn7u2er2ikvnmtxxa";
  };
  # LaunchInstance's availabilityDomain field wants the AD's human-readable
  # name (e.g. "Uocm:PHX-AD-1"), not its OCID — passing the OCID here is
  # what caused every launch to fail with 400 CannotParseRequest even
  # though the rest of the request was well-formed. VHDx:AP-MUMBAI-1-AD-1
  # is the only AD in this home region.
  variable.oci_availability_domain = {
    type = "string";
    default = "VHDx:AP-MUMBAI-1-AD-1";
  };
  # subnet-ankcloud in vcn-ankcloud — the only VCN/subnet in this tenancy.
  variable.oci_subnet_ocid = {
    type = "string";
    default = "ocid1.subnet.oc1.ap-mumbai-1.aaaaaaaa256r5znqzi3qzsj7zr6haajyczyhpokz2zij3wtqivoreri5yyba";
  };
  # Canonical-Ubuntu-24.04-Minimal-aarch64-2026.07.17-0. nixos-anywhere kexecs
  # into its own installer and wipes/repartitions per disko, so the initial
  # image just needs to boot, offer SSH as a sudo-capable `ubuntu` user, and
  # support kexec — the minimal variant boots faster and its extra packages
  # over the full image are irrelevant since they get overwritten anyway.
  variable.oci_image_ocid = {
    type = "string";
    default = "ocid1.image.oc1.ap-mumbai-1.aaaaaaaa4fenm3xymugnh3xgdrey3h2gr6aluzh4efk3auya4ml6yg6shcqq";
  };
  variable.oci_ssh_public_key = {
    type = "string";
    # The ed25519 agenix key baked into hosts/nixos/VPS0/VPS0.nix's
    # authorizedKeys — needed so bootstrap-remote/nixos-anywhere can SSH in
    # right after commissioning. A prior manual instance launch used a
    # throwaway RSA key here instead, which locked our own tooling out.
    default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiaeSJP9C/rfe4nldhwrXjCJ3qP4qTWreR4lHMr/1BI";
  };
  variable.oci_shape = {
    type = "string";
    default = "VM.Standard.A1.Flex";
  };
  variable.oci_ocpus = {
    type = "number";
    # This tenancy's actual standard-a1-core-count service limit is 2 (not
    # the oft-cited 4 OCPU Always Free ceiling) — confirmed via `oci limits
    # resource-availability get` after terminating the prior 2 OCPU/12GB
    # VPS0 on 2026-08-18; a 4 OCPU request 400s with LimitExceeded.
    default = 2;
  };
  variable.oci_memory_in_gbs = {
    type = "number";
    default = 12;
  };
  variable.oci_display_name = {
    type = "string";
    default = "VPS0";
  };

  provider.oci = {
    tenancy_ocid = "\${var.oci_tenancy_ocid}";
    user_ocid = "\${var.oci_user_ocid}";
    fingerprint = "\${var.oci_fingerprint}";
    private_key_path = "\${var.oci_private_key_path}";
    region = "\${var.oci_region}";
  };

  resource.oci_core_instance.O1 = {
    availability_domain = "\${var.oci_availability_domain}";
    compartment_id = "\${var.oci_compartment_ocid}";
    display_name = "\${var.oci_display_name}";
    shape = "\${var.oci_shape}";
    create_vnic_details = {
      subnet_id = "\${var.oci_subnet_ocid}";
      assign_public_ip = true;
    };
    source_details = {
      source_type = "image";
      source_id = "\${var.oci_image_ocid}";
    };
    shape_config = {
      ocpus = "\${var.oci_ocpus}";
      memory_in_gbs = "\${var.oci_memory_in_gbs}";
    };
    metadata.ssh_authorized_keys = "\${var.oci_ssh_public_key}";
  };
}
