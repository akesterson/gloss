#!/usr/bin/env bash4

source /usr/lib/tunit.sh
source /usr/lib/junit.sh
source /usr/lib/cmdarg.sh

function failearly
{
    echo "$1" >&2
    exit 1
}

function gloss_man
{
    which ronn >/dev/null 2>&1 || failearly "You don't appear to have ronn, or it's not in your path"
    local files targets format
    declare -a files
    declare -a targets
    format=${cmdarg_cfg['format']}
    files=($(find ${cmdarg_cfg['man_dir']} -iname '*.[0-9].md'))
    targets=($(find ${cmdarg_cfg['man_dir']} -iname '*.[0-9].md' | sed s/'\.\([0-9]\)\.md'/'\.\1\.gz'/))

    manual=$(echo "${cmdarg_cfg['manual_name']}" | sed s/'^nil$'/''/)

    for idx in "${!files[@]}"; do
	local source dest
	source=${files[$idx]}
	dest=${targets[$idx]}
	err=$(ronn --manual "$manual" --style=80c,man --date $(date "+%Y-%m-%d") --man $source | gzip > $dest 2>&1)
	if [[ $? -ne 0 ]]; then
	    ${format}_testcase 'man' "$manual::$source" 0 "ronn" "$(echo \"$err\" | head -n 1)" "$(echo $err)"
	else
	    ${format}_testcase 'man' "$manual::$source" 0
	fi
    done

    if [[ "${cmdarg_cfg['tarball']}" ]]; then
	if [[ "$manual" == "" ]]; then
	    ${format}_testcase 'man' "package:$manual" 0 "ronn" "Must provide -M when packaging man pages" ""
	else
	    mkdir -p .gloss.$$/man
	    for file in ${targets[@]}
	    do
		section=$(echo $file | sed s/'.*\.\([0-9]\)\.gz'/'\1'/)
		mkdir -p .gloss.$$/man/man${section}
		cp $file .gloss.$$/man/man${section}/
	    done

	    err=$(cd .gloss.$$ && tar -czf ${cmdarg_cfg['output']}/${manual}-$(date "+%Y-%m-%d").tar.gz man 2>&1)
	    if [[ $? -ne 0 ]]; then
		${format}_testcase 'man' "$manual::" 0 "tar" "$(echo \"$err\" | head -n 1)" "$(echo $err)"
	    else
		${format}_testcase 'man' "$manual::package" 0
	    fi
	    rm -fr .gloss.$$
	fi
    fi
}

function gloss_wiki
{
    which markdown2confluence >/dev/null 2>&1 || failearly "You don't appear to have markdown2confluence, or it's not in your path"

    validate=wiki_dir
    if [[ "${cmdarg_cfg['publish_wiki']}" == "true" ]]; then
	validate="$validate wiki_url wiki_user wiki_password wiki_space"
    fi
    for key in $validate
    do
	if [[ "${cmdarg_cfg[$key]}" == "nil" ]]; then
	    failearly "${CMDARG_REV[$key]} is required"
	fi
    done
    if [[ ! -d ${cmdarg_cfg['wiki_dir']} ]]; then
	echo "${cmdarg_cfg['wiki_dir']} does not exist" >&2
	return
    fi

    local files targets format
    format=${cmdarg_cfg['format']}
    declare -a files
    declare -a targets
    cd ${cmdarg_cfg['wiki_dir']}
    OLDIFS=$IFS
    IFS=$'\n' files=($(find -iname '*.md' | sed s/'\.\/'//g))
    IFS=$OLDIFS
    spaceroot=$(echo ${cmdarg_cfg['wiki_space']})

    for idx in ${!files[@]}
    do
	parent=""
	page=${files[$idx]}
	pagetitle=$(basename "$page" | sed s/'\.md$'/''/)
	basepage=$(basename "$page")
	pagedir=$(dirname "$page")
	wikipath="$(echo ${cmdarg_cfg['wiki_space']} | grep -v '^nil$')/$(echo $page | sed s/\.md//g)"
	# This is just to make it work on cygwin with ruby that doesn't understand symlinks
	cat "$page" > .tmp.$$
	err=$(markdown2confluence .tmp.$$ > "${pagedir}/${basepage}".confluence)
	RC=$?
	rm -f .tmp.$$
	if [[ $RC -ne 0 ]]; then
	    ${format}_testcase 'confluence' "${cmdarg_cfg['wiki_dir']}/$page" 0 "markdown2confluence" "$(echo \"$err\" | head -n 1)" "$(echo $err)"
	else
	    ${format}_testcase 'confluence' "${cmdarg_cfg['wiki_dir']}/$page" 0
	fi
	if [[ "${cmdarg_cfg['publish_wiki']}" == "true" ]]; then
	    OLDIFS=$IFS
	    IFS=$'\n' sections=($(echo "$pagedir" | tr '/' '\n'))
	    IFS=$OLDIFS
	    for idx in ${!sections[@]}
	    do
		section="${sections[$idx]}"
		newerr=$(/opt/atlassian-cli/confluence.sh \
		    --server ${cmdarg_cfg['wiki_url']} \
		    --user ${cmdarg_cfg['wiki_username']} \
		    --password ${cmdarg_cfg['wiki_password']} \
		    -a getSource \
		    --space "$spaceroot" \
		    --parent "$parent" \
		    --title "$section" 2>&1)
		if [[ $? -ne 0 ]]; then
		    err="${err}${newerr}"
		    newerr=$(/opt/atlassian-cli/confluence.sh \
			--server ${cmdarg_cfg['wiki_url']} \
			--user ${cmdarg_cfg['wiki_username']} \
			--password ${cmdarg_cfg['wiki_password']} \
			-a addPage \
			--space "$spaceroot" \
			--parent "$parent" \
			--title "$section" \
			--replace \
			--content 'There is nothing here, please see the subpages' 2>&1)
		fi
		err="${err}${newerr}"
		parent="$section"
	    done
	    newerr=$(/opt/atlassian-cli/confluence.sh \
		--server ${cmdarg_cfg['wiki_url']} \
		--user ${cmdarg_cfg['wiki_username']} \
		--password ${cmdarg_cfg['wiki_password']} \
		-a addPage \
		--space "$spaceroot" \
		--parent "$parent" \
		--title "$pagetitle" \
		--file "$page".confluence \
		--replace 2>&1)
	    RC=$?
	    err="${err}${newerr}"
	    if [[ $? -ne 0 ]]; then
		${format}_testcase 'confluence:publish' "${cmdarg_cfg['wiki_dir']}/$page" 0 "atlassian-cli" "$(echo \"$err\" | head -n 1)" "$(echo $err)"
	    else
		${format}_testcase 'confluence:publish' "${cmdarg_cfg['wiki_dir']}/$page" 0
	    fi
	fi
    done
}

function main()
{
    cmdarg_purge
    cmdarg_info header "A script for publishing a directory of documentation files into MAN and Confluence. Requires ruby, and the ronn and markdown2confluence gems."
    cmdarg_info copyright "(MIT License)"
    cmdarg_info author "Andrew Kesterson <andrew@aklabs.net>"

    cmdarg 'o:' 'output' 'Write resulting file(s) into this directory' "$(pwd)"
    cmdarg 'm:' 'man_dir' 'Directory containing MARKDOWN files to convert to MAN. Files must be named *.[0-9].md, where [0-9] is their intended man section.' './man'
    cmdarg 'w:' 'wiki_dir' 'Directory containing MARKDOWN files to convert to Confluence.' './wiki'
    cmdarg 't' 'tarball' 'Produce a single tarball package of all man files in the output directory. REQUIRES -M.'
    cmdarg 'p' 'publish_wiki' 'Publish Confluence content to Confluence'
    cmdarg 'H' 'publish_html' 'Create Standalone HTML documentation'
    cmdarg 'M:' 'manual_name' 'The name of the manual that all pages should belong to. Leave unset for no manual name.' 'nil'
    cmdarg 'W:' 'wiki_url' 'URL of your confluence instance' 'nil'
    cmdarg 'U:' 'wiki_username' 'Username to connect to Confluence as' 'nil'
    cmdarg 'P:' 'wiki_password' 'Password to connect to Confluence' 'nil'
    cmdarg 'S:' 'wiki_space' 'Space into the wiki (can be pathed ala Space Name/Page/SubPage) to begin publishing' 'nil'
    cmdarg 'c:' 'confluence_bin' 'Confluence command line API binary' '/opt/atlassian-cli/bin/confluence.sh'
    cmdarg 'f:' 'format' 'Format to report results in. (tunit|junit)' 'tunit'
    cmdarg_parse "$@"

    format=${cmdarg_cfg['format']}
    ${format}_header
    gloss_man
    RC=$?
    gloss_wiki
    RC=$((RC + $?))
    ${format}_footer

    exit $RC
}

main "$@"
