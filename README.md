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

# Prerequisites

You will need Ruby - versions 2.4.x and 2.5.x have been tested. You will also
need aws-sdk-cloudwatch:

    $ gem install aws-sdk-cloudwatch

# Usage

As the amount of metrics is generally quite large - even for a single AWS
resource - this plugin depends on a yaml configuration file. An example is
provided for AWS RDS, see [config.yaml.sample](config.yaml.sample). The
assumption is that a single config file targets one AWS resource (e.g. RDS
instance). Note that metric names should be kept really short as Nagios plugins
only support labels of [19 characters or less](https://nagios-plugins.org/doc/guidelines.html#AEN200).

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

To run the code in debug mode (not suitable for running in a monitoring
system):

    $ ./check_cloudwatch -c my_db_instance.yaml -d

# Settings

There are a few global (per nagios plugin instance) settings that you may want to tweak:

* precision: the rounding precision for floats - defaults to 2
* period: the metric period to use - defaults 300 (5 minutes)
* metric_age: reduce this many seconds from start and end time - useful with some odd metrics like BurstBalance that fail to provide data point for "now - period" 

# Plugin output

Plugin output is based on the format described here, without "min" or "max":

* https://nagios-plugins.org/doc/guidelines.html#AEN200

When no thresholds are exceeded (split to multiple lines for clarity) the
output will be similar to this:

    AWS/RDS my-db-instance OK | cpu_utilization_percent_average=6.1%;30;50;; \
                                cpu_utilization_percent_maximum=7.5%;;;; \
                                cpu_utilization_percent_minimum=5.67%;;;; \
                                swap_usage_bytes_average=0.0B;;;;
                                free_storage_space_bytes_minimum=103730221056.0B;;;; \
                                database_connections_count_average=8.0;;;; \
                                read_latency_seconds_average=0.0;;;; \
                                write_latency_seconds_average=0.0;;;;

In case of warnings and/or errors the first part of the output looks different:

    AWS/RDS my-db-instance \
      WARNING: cpu_utilization_percent_average=6.0 exceeds the threshold of 3.0! \
      CRITICAL: database_connections_count_average=8.0 exceeds the threshold of 7.0!

# LICENSE

This plugin is released under the terms of the [GPLv2 license](LICENSE).
