# nagios-plugin-cloudwatch

This is a Nagios plugin that gets metrics from AWS Cloudwatch using the
GetMetricStatistics API call. Alerts can be configured for each metric
statistic (e.g. average CPU usage) individually. Both warning and critical
alert thresholds are configurable.

If alerts are configured for multiple metric statistics this plugin aggregates
the overall alert status. For example, if one statistic exceeds the the warning
threshold and another one exceeds the critical threshold then the plugin will
exit with critical status (1), but include both the warning and the critical
error in the informal error message.

# Usage

As the amount of metrics is generally quite large - even for a single AWS
resource - this plugin depends on a yaml configuration file. An example is
provided for AWS RDS, see [config.yaml.sample](config.yaml.sample). The
assumption is that a single config file targets one AWS resource (e.g. RDS
instance).

IAM user, key and policy are needed to access Cloudwatch metrics. An
example IAM policy:

    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "VisualEditor0",
                "Effect": "Allow",
                "Action": [
                    "cloudwatch:ListMetrics",
                    "cloudwatch:GetMetricStatistics"
                ],
                "Resource": "*"
            }
        ]
    }

After this you just call the plugin like this:

    $ ./check_cloudwatch -c my_db_instance.yaml

# Plugin output

When no thresholds are exceeded (split to multiple lines for clarity):

    AWS/RDS my-db-instance OK | cpu_utilization_percent_average=6.1, \
                                cpu_utilization_percent_maximum=7.5, \
                                cpu_utilization_percent_minimum=5.67, \
                                swap_usage_bytes_average=0.0,
                                free_storage_space_bytes_minimum=103730221056.0, \
                                database_connections_count_average=8.0, \
                                read_latency_seconds_average=0.0, \
                                write_latency_seconds_average=0.0

In case of warnings and/or errors the first part of the output looks different:

    AWS/RDS my-db-instance \
      WARNING: cpu_utilization_percent_average=6.0 exceeds the warning threshold of 3.0! \
      CRITICAL: database_connections_count_average=8.0 exceeds the critical threshold of 7.0!

# LICENSE

This plugin is released under the terms of the [GPLv2 license](LICENSE).
