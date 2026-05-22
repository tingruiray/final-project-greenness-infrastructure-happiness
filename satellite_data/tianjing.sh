#!/bin/bash

GREP_OPTIONS=''

cookiejar=$(mktemp cookies.XXXXXXXXXX)
netrc=$(mktemp netrc.XXXXXXXXXX)
chmod 0600 "$cookiejar" "$netrc"
function finish {
  rm -rf "$cookiejar" "$netrc"
}

trap finish EXIT
WGETRC="$wgetrc"

prompt_credentials() {
    echo "Enter your Earthdata Login or other provider supplied credentials"
    read -p "Username (tingrui779944537): " username
    username=${username:-tingrui779944537}
    read -s -p "Password: " password
    echo "machine urs.earthdata.nasa.gov login $username password $password" >> $netrc
    echo
}

exit_with_error() {
    echo
    echo "Unable to Retrieve Data"
    echo
    echo $1
    echo
    echo "https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018360T030121.v2.0/HLS.S30.T50TNK.2018360T030121.v2.0.Fmask.tif"
    echo
    exit 1
}

prompt_credentials
  detect_app_approval() {
    approved=`curl -s -b "$cookiejar" -c "$cookiejar" -L --max-redirs 5 --netrc-file "$netrc" https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018360T030121.v2.0/HLS.S30.T50TNK.2018360T030121.v2.0.Fmask.tif -w '\n%{http_code}' | tail  -1`
    if [ "$approved" -ne "200" ] && [ "$approved" -ne "301" ] && [ "$approved" -ne "302" ]; then
        # User didn't approve the app. Direct users to approve the app in URS
        exit_with_error "Please ensure that you have authorized the remote application by visiting the link below "
    fi
}

setup_auth_curl() {
    # Firstly, check if it require URS authentication
    status=$(curl -s -z "$(date)" -w '\n%{http_code}' https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018360T030121.v2.0/HLS.S30.T50TNK.2018360T030121.v2.0.Fmask.tif | tail -1)
    if [[ "$status" -ne "200" && "$status" -ne "304" ]]; then
        # URS authentication is required. Now further check if the application/remote service is approved.
        detect_app_approval
    fi
}

setup_auth_wget() {
    # The safest way to auth via curl is netrc. Note: there's no checking or feedback
    # if login is unsuccessful
    touch ~/.netrc
    chmod 0600 ~/.netrc
    credentials=$(grep 'machine urs.earthdata.nasa.gov' ~/.netrc)
    if [ -z "$credentials" ]; then
        cat "$netrc" >> ~/.netrc
    fi
}

fetch_urls() {
  if command -v curl >/dev/null 2>&1; then
      setup_auth_curl
      while read -r line; do
        # Get everything after the last '/'
        filename="${line##*/}"

        # Strip everything after '?'
        stripped_query_params="${filename%%\?*}"

        curl -f -b "$cookiejar" -c "$cookiejar" -L --netrc-file "$netrc" -g -o $stripped_query_params -- $line && echo || exit_with_error "Command failed with error. Please retrieve the data manually."
      done;
  elif command -v wget >/dev/null 2>&1; then
      # We can't use wget to poke provider server to get info whether or not URS was integrated without download at least one of the files.
      echo
      echo "WARNING: Can't find curl, use wget instead."
      echo "WARNING: Script may not correctly identify Earthdata Login integrations."
      echo
      setup_auth_wget
      while read -r line; do
        # Get everything after the last '/'
        filename="${line##*/}"

        # Strip everything after '?'
        stripped_query_params="${filename%%\?*}"

        wget --load-cookies "$cookiejar" --save-cookies "$cookiejar" --output-document $stripped_query_params --keep-session-cookies -- $line && echo || exit_with_error "Command failed with error. Please retrieve the data manually."
      done;
  else
      exit_with_error "Error: Could not find a command-line downloader.  Please install curl or wget"
  fi
}

fetch_urls <<'EDSCEOF'
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018360T030121.v2.0/HLS.S30.T50TNK.2018360T030121.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018360T030121.v2.0/HLS-VI.S30.T50TNK.2018360T030121.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018358T031129.v2.0/HLS.S30.T50SMH.2018358T031129.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018358T031129.v2.0/HLS-VI.S30.T50SMH.2018358T031129.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018355T030129.v2.0/HLS.S30.T50TNK.2018355T030129.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018355T030129.v2.0/HLS-VI.S30.T50TNK.2018355T030129.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018350T030121.v2.0/HLS.S30.T50SMH.2018350T030121.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018350T030121.v2.0/HLS-VI.S30.T50SMH.2018350T030121.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018348T031129.v2.0/HLS.S30.T50SMH.2018348T031129.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018348T031129.v2.0/HLS-VI.S30.T50SMH.2018348T031129.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018338T031109.v2.0/HLS.S30.T50SMH.2018338T031109.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018338T031109.v2.0/HLS-VI.S30.T50SMH.2018338T031109.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018325T030019.v2.0/HLS.S30.T50TNK.2018325T030019.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018325T030019.v2.0/HLS-VI.S30.T50TNK.2018325T030019.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018320T030001.v2.0/HLS.S30.T50SMH.2018320T030001.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018320T030001.v2.0/HLS-VI.S30.T50SMH.2018320T030001.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018305T025839.v2.0/HLS.S30.T50TNK.2018305T025839.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018305T025839.v2.0/HLS-VI.S30.T50TNK.2018305T025839.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018300T025811.v2.0/HLS.S30.T50SMH.2018300T025811.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018300T025811.v2.0/HLS-VI.S30.T50SMH.2018300T025811.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018280T025601.v2.0/HLS.S30.T50TNK.2018280T025601.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018280T025601.v2.0/HLS-VI.S30.T50TNK.2018280T025601.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018275T025539.v2.0/HLS.S30.T50TNK.2018275T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018275T025539.v2.0/HLS-VI.S30.T50TNK.2018275T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TMK.2018275T025539.v2.0/HLS.S30.T50TMK.2018275T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018275T025539.v2.0/HLS-VI.S30.T50TMK.2018275T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018275T025539.v2.0/HLS.S30.T50SMH.2018275T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018275T025539.v2.0/HLS-VI.S30.T50SMH.2018275T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SNH.2018265T025539.v2.0/HLS.S30.T50SNH.2018265T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNH.2018265T025539.v2.0/HLS-VI.S30.T50SNH.2018265T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018265T025539.v2.0/HLS.S30.T50SMH.2018265T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018265T025539.v2.0/HLS-VI.S30.T50SMH.2018265T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018265T025539.v2.0/HLS.S30.T50TNK.2018265T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018265T025539.v2.0/HLS-VI.S30.T50TNK.2018265T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SNJ.2018155T025539.v2.0/HLS.S30.T50SNJ.2018155T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018155T025539.v2.0/HLS-VI.S30.T50SNJ.2018155T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018155T025539.v2.0/HLS.S30.T50SMH.2018155T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018155T025539.v2.0/HLS-VI.S30.T50SMH.2018155T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018150T025551.v2.0/HLS.S30.T50SMH.2018150T025551.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018150T025551.v2.0/HLS-VI.S30.T50SMH.2018150T025551.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018115T025549.v2.0/HLS.S30.T50TNK.2018115T025549.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018115T025549.v2.0/HLS-VI.S30.T50TNK.2018115T025549.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018110T025551.v2.0/HLS.S30.T50SMH.2018110T025551.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018110T025551.v2.0/HLS-VI.S30.T50SMH.2018110T025551.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018108T030539.v2.0/HLS.S30.T50SMH.2018108T030539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018108T030539.v2.0/HLS-VI.S30.T50SMH.2018108T030539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TMK.2018105T025539.v2.0/HLS.S30.T50TMK.2018105T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018105T025539.v2.0/HLS-VI.S30.T50TMK.2018105T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMJ.2018105T025539.v2.0/HLS.S30.T50SMJ.2018105T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018105T025539.v2.0/HLS-VI.S30.T50SMJ.2018105T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018105T025539.v2.0/HLS.S30.T50TNK.2018105T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018105T025539.v2.0/HLS-VI.S30.T50TNK.2018105T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018098T030539.v2.0/HLS.S30.T50SMH.2018098T030539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018098T030539.v2.0/HLS-VI.S30.T50SMH.2018098T030539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TMK.2018098T030539.v2.0/HLS.S30.T50TMK.2018098T030539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TMK.2018098T030539.v2.0/HLS-VI.S30.T50TMK.2018098T030539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018088T030539.v2.0/HLS.S30.T50TNK.2018088T030539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018088T030539.v2.0/HLS-VI.S30.T50TNK.2018088T030539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018075T025539.v2.0/HLS.S30.T50TNK.2018075T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018075T025539.v2.0/HLS-VI.S30.T50TNK.2018075T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018075T025539.v2.0/HLS.S30.T50SMH.2018075T025539.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018075T025539.v2.0/HLS-VI.S30.T50SMH.2018075T025539.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018055T025709.v2.0/HLS.S30.T50TNK.2018055T025709.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018055T025709.v2.0/HLS-VI.S30.T50TNK.2018055T025709.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018038T030859.v2.0/HLS.S30.T50SMH.2018038T030859.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018038T030859.v2.0/HLS-VI.S30.T50SMH.2018038T030859.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018035T025919.v2.0/HLS.S30.T50SMH.2018035T025919.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018035T025919.v2.0/HLS-VI.S30.T50SMH.2018035T025919.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50TNK.2018030T030631.v2.0/HLS.S30.T50TNK.2018030T030631.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50TNK.2018030T030631.v2.0/HLS-VI.S30.T50TNK.2018030T030631.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMJ.2018013T031101.v2.0/HLS.S30.T50SMJ.2018013T031101.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMJ.2018013T031101.v2.0/HLS-VI.S30.T50SMJ.2018013T031101.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SNJ.2018010T030631.v2.0/HLS.S30.T50SNJ.2018010T030631.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SNJ.2018010T030631.v2.0/HLS-VI.S30.T50SNJ.2018010T030631.v2.0.TVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30.020/HLS.S30.T50SMH.2018005T030109.v2.0/HLS.S30.T50SMH.2018005T030109.v2.0.Fmask.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.EVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.MSAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.NBR.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.NBR2.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.NDMI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.NDVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.NDWI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.SAVI.tif
https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T50SMH.2018005T030109.v2.0/HLS-VI.S30.T50SMH.2018005T030109.v2.0.TVI.tif
EDSCEOF