# @summary: Bootstraps Percona Server as master or configures as replica.
# Creates MySQL users on master (replicas get them via replication).
# Registers instances with NLB target groups.
class profile::percona::bootstrap () {

  $cluster_id = $facts['percona']['cluster_id']
  $dynamodb_table = $facts['percona']['dynamodb_table']
  $credentials_secret = $facts['percona']['credentials_secret']
  $vpc_cidr = $facts['percona']['vpc_cidr']
  $read_tg_arn = $facts['percona']['read_tg_arn']
  $write_tg_arn = $facts['percona']['write_tg_arn']

  $bootstrap_cmd = @("CMD"/L)
    ih-mysql bootstrap \
    --cluster-id ${cluster_id} \
    --dynamodb-table ${dynamodb_table} \
    --credentials-secret ${credentials_secret} \
    --vpc-cidr ${vpc_cidr} \
    --read-tg-arn ${read_tg_arn} \
    --write-tg-arn ${write_tg_arn}
    |-CMD

  exec { 'percona-bootstrap':
    path    => '/usr/local/bin:/usr/bin:/bin',
    command => $bootstrap_cmd,
    creates => '/var/lib/mysql/.bootstrapped',
    require => [
      Package['infrahouse-toolkit'],
      Service['mysql'],
    ],
  }

}