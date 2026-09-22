# compile.jq — registry.yaml (as JSON, via `yq -o=json`) -> catalog.json.
# Invoked by `pf.sh compile`. Pure data transform, never touches the cluster.
#
# Usage: jq -f compile.jq --arg generated_at "$ts" registry.json > catalog.json
#
# Two target shapes in registry.yaml:
#   A) "uniform" (e.g. severino-v2): envs:[...], resource, remote_port,
#      local_port:{env:port}. Same resource name in every env, ns_role=app.
#   B) "per_env" (datastores/observability): per_env:{env:{ns_role,resource,
#      remote_port|ports,local_port,risk?,secret_ref?}}.

def ports_single(remote; local):
  [{name: "default", remote: remote, local: local}];

def ports_multi(ports; locals):
  ports | to_entries | map({name: .key, remote: .value, local: locals[.key]});

(.environments) as $envs
| (.aliases // {}) as $aliases
| {
    version: 1,
    generated_at: $generated_at,
    compiled_from: "registry.yaml",
    environments: $envs,
    aliases: $aliases,
    entries: [
      (.targets | to_entries[]) as $t
      | ($t.key) as $tname
      | ($t.value) as $tval
      | (
          if ($tval.envs != null) then
            ($tval.envs[]) as $e
            | {
                id: ($e + "-" + $tname),
                env: $e,
                target: $tname,
                kind: ($tval.kind // "app"),
                ns_role: "app",
                namespace: $envs[$e].namespaces.app,
                context: $envs[$e].context,
                resource: $tval.resource,
                ports: ports_single($tval.remote_port; $tval.local_port[$e]),
                risk: ($envs[$e].risk),
                secret_ref: null,
                source: "curated",
                discovered_at: null,
                verified_at: null
              }
          else
            (($tval.per_env // {}) | to_entries[]) as $pe
            | ($pe.key) as $e
            | ($pe.value) as $pv
            | {
                id: ($e + "-" + $tname),
                env: $e,
                target: $tname,
                kind: ($tval.kind // "datastore"),
                ns_role: ($pv.ns_role // "app"),
                namespace: $envs[$e].namespaces[($pv.ns_role // "app")],
                context: $envs[$e].context,
                resource: $pv.resource,
                ports: (
                  if ($pv.ports != null) then ports_multi($pv.ports; $pv.local_port)
                  else ports_single($pv.remote_port; $pv.local_port)
                  end
                ),
                risk: ($pv.risk // $envs[$e].risk),
                secret_ref: ($pv.secret_ref // null),
                source: "curated",
                discovered_at: null,
                verified_at: null
              }
          end
        )
    ]
  }
