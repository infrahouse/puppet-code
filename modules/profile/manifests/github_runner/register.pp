# @summary: registers the runner.
class profile::github_runner::register (
  $runner_labels,
  $runner_package_directory,
  $token_secret,
  $org,
  $url,
  $user,
) {

  $hostname = $facts['networking']['hostname']
  $instance_id = $facts['ec2_metadata']['instance-id']
  $labels = ($runner_labels + ["instance_id:${instance_id}"] + $facts['labels']).map |$label| {
    if $label { "--label ${label}" }
    else { '' }
  }
  $labels_arg = join($labels, ' ')

  exec { 'register_runner':
    user    => $user,
    path    => "/usr/bin:/usr/local/bin:${runner_package_directory}",
    cwd     => $runner_package_directory,
    command => "ih-github runner --github-token-secret ${token_secret} --org ${org} register \
--actions-runner-code-path ${runner_package_directory} ${url} ${labels_arg}",
    unless  => "ih-github runner --github-token-secret ${token_secret} --org ${org} is-registered ${hostname}",
    require => [
      Exec[extract_runner_package]
    ]
  }
}
