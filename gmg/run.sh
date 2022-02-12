#!/usr/bin/env bashio

conf_directory="/config/gmg"

if bashio::services.available "mqtt"; then
    host=$(bashio::services "mqtt" "host")
    password=$(bashio::services "mqtt" "password")
    port=$(bashio::services "mqtt" "port")
    username=$(bashio::services "mqtt" "username")
    retain=$(bashio::config "retain")
else
    bashio::log.info "The mqtt addon is not available."
    bashio::log.info "Manually update the output line in the configuration file with mqtt connection settings, and restart the addon."
fi

if [ ! -d $conf_directory ]
then
    mkdir -p $conf_directory
fi

# Check if the legacy configuration file is set and alert that it's deprecated.
conf_file=$(bashio::config "gmg_conf_file")

if [[ $conf_file != "" ]]
then
    bashio::log.warning "gmgtest."
    conf_file="/config/$conf_file"

    echo "Starting gmg -c $conf_file"
    gmg -c "$conf_file"
    exit $?
fi

# Create a reasonable default configuration in /config/gmg.
if [ ! "$(ls -A $conf_directory)" ]
then
    cat > $conf_directory/gmg.conf.template <<EOD
# This is an empty template for configuring gmg. mqtt information will be
# automatically added. Create multiple files ending in '.conf.template' to
# manage multiple rtl_433 radios, being sure to set the 'device' setting.
# https://github.com/merbanan/rtl_433/blob/master/conf/rtl_433.example.conf

output mqtt://\${host}:\${port},user=\${username},pass=\${password},retain=\${retain}

# Uncomment the following line to also enable the default "table" output to the
# addon logs.
# output kv
EOD
fi

# Remove all rendered configuration files.
rm -f $conf_directory/*.conf

gmg_pids=()
for template in $conf_directory/*.conf.template
do
    # Remove '.template' from the file name.
    live=$(basename $template .template)

    # By sourcing the template, we can substitute any environment variable in
    # the template. In fact, enterprising users could write _any_ valid bash
    # to create the final configuration file. To simplify template creation,
    # we wrap the needed redirections into a temparary file.
    echo "cat <<EOD > $live" > /tmp/gmg_heredoc
    cat $template >> /tmp/gmg_heredoc
    echo EOD >> /tmp/gmg_heredoc

    source /tmp/gmg_heredoc

    echo "Starting gmg with $live..."
    tag=$(basename $live .conf)
    gmg -c "$live" > >(sed "s/^/[$tag] /") 2> >(>&2 sed "s/^/[$tag] /")&
    gmg_pids+=($!)
done

wait -n ${gmg_pids[*]}
