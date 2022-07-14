#!/bin/bash

set -u
#set -e

VER=${1:?Need ver}
PKGDIR=$VER
VVER=`echo $VER | tr -d "." | tr -d "-"`

function check_curl_error() {
        RV=$1
        WHAT=$2

        if [[ ($RV != 200) && ($RV != 201) && ($RV != 202) && ($RV != 204) ]] ; then
                echo "Error:$RV    Artifactory: $WHAT"
                echo "More details:"
                cat /tmp/Acurl.out
                #exit $RV
        fi

}

ARKEY="foo"


cd $PKGDIR
for R in `ls -1 *$VER*.rpm`
do
        RV=`curl -i --write-out %{http_code} -o /tmp/Acurl.out -H 'X-JFrog-Art-Api:AKCp8ii9EG3o6W7MeTpCt3LqNKM2XhH23x9TYc3om4CSxh26bjBjmJeMxYQyQbkKepdjvoLHU' -XPUT https://urm.nvidia.com/artifactory/sw-ngn-sdn-rpm/sdn/nm/8/x86_64/ -T $R`
        check_curl_error $RV "XPUT $R"
        echo "Uploaded $R to urm.nvidia.com/artifactory/sw-ngn-sdn-rpm/sdn/nm/8/x86_64/"

done
cd -
sed s/VeRsIoN/$VER/ rpmNMbundle.j2 > rpmNMbundle.json
sed -i s/VVER/$VVER/ rpmNMbundle.json
RV=`curl -i --write-out %{http_code} -o /tmp/Acurl.out -u sklein:$ARKEY -H "Accept: application/json" -H "Content-Type: application/json"  -XPOST  https://urm.nvidia.com/distribution/api/v1/release_bundle -T rpmNMbundle.json`
check_curl_error $RV "Create Bundle for NM"

RV=`curl -i --write-out %{http_code} -o /tmp/Acurl.out -u sklein:$ARKEY -H "Accept: application/json" -H "Content-Type: application/json"  -XPOST  https://urm.nvidia.com/distribution/api/v1/distribution/sw-ngn-sdn-rpm-nm/rpm${VVER} -T distribution.json`
check_curl_error $RV "Distribute rpm${VVER}"

cd $PKGDIR
for R in `ls -1 *$VER*.deb`
do
        RV=`curl -i --write-out %{http_code} -o /tmp/Acurl.out -H 'X-JFrog-Art-Api:AKCp8ii9EG3o6W7MeTpCt3LqNKM2XhH23x9TYc3om4CSxh26bjBjmJeMxYQyQbkKepdjvoLHU' -XPUT "https://urm.nvidia.com/artifactory/sw-ngn-sdn-debian/nm/ngn/$R;deb.distribution=focal;deb.component=main;deb.architecture=arm64" -T $R`
        check_curl_error $RV "XPUT $R"
        echo "Uploaded $R to urm.nvidia.com/artifactory/sw-ngn-sdn-debian/nm/ngn/$R"

done
cd -
sed s/VeRsIoN/$VER/ debNMbundle.j2 > debNMbundle.json
sed -i s/VVER/$VVER/ debNMbundle.json
RV=`curl -i --write-out %{http_code} -o /tmp/Acurl.out -u sklein:$ARKEY -H "Accept: application/json" -H "Content-Type: application/json"  -XPOST  https://urm.nvidia.com/distribution/api/v1/release_bundle -T debNMbundle.json`
check_curl_error $RV "Create Bundle for deb NM"

RV=`curl -i --write-out %{http_code} -o /tmp/Acurl.out -u sklein:$ARKEY -H "Accept: application/json" -H "Content-Type: application/json"  -XPOST  https://urm.nvidia.com/distribution/api/v1/distribution/sw-ngn-sdn-debian-nm/deb${VVER} -T distribution.json`
check_curl_error $RV "Distribute sw-ngn-sdn-debian-nm"

