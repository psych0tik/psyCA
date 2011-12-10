#!/bin/sh
#
# CA - wrapper around ca to make it easier to use ... basically ca requires
#      some setup stuff to be done before you can use it and this makes
#      things easier between now and when Eric is convinced to fix it :-)
#
# CA -newca ... will setup the right stuff
# CA -newreq ... will generate a certificate request
# CA -sign ... will sign the generated request and output
#
# At the end of that grab newreq.pem and newcert.pem (one has the key
# and the other the certificate) and cat them together and that is what
# you want/need ... I'll make even this a little cleaner later.
#
#
# 12-Jan-96 tjh    Added more things ... including CA -signcert which
#                  converts a certificate to a request and then signs it.
# 10-Jan-96 eay    Fixed a few more bugs and added the SSLEAY_CONFIG
#                  environment variable so this can be driven from
#                  a script.
# 25-Jul-96 eay    Cleaned up filenames some more.
# 11-Jun-96 eay    Fixed a few filename missmatches.
# 03-May-96 eay    Modified to use 'ssleay cmd' instead of 'cmd'.
# 18-Apr-96 tjh    Original hacking
# 05-Nov-11 clf    Massive Overhaul
#
# Tim Hudson
# tjh@cryptsoft.com
#

# default openssl.cnf file has setup as per the following
# demoCA ... where everything is stored
cp_pem() {
    infile=$1
    outfile=$2
    bound=$3
    flag=0
    exec <$infile;
    while read line; do
	if [ $flag -eq 1 ]; then
		echo $line|grep "^-----END.*$bound"  2>/dev/null 1>/dev/null
		if [ $? -eq 0 ] ; then
			echo $line >>$outfile
			break
		else
			echo $line >>$outfile
		fi
	fi

	echo $line|grep "^-----BEGIN.*$bound"  2>/dev/null 1>/dev/null
	if [ $? -eq 0 ]; then
		echo $line >$outfile
		flag=1
	fi
    done
}

is_mode() {
    echo $1 >&2
     case "$1" in
	 -newcert|-newreq|-newreq-nodes|-newca|-xsign|-pkcs11|-sign|-signreq|-signCA|-signcert|-verify|-exterminate)
	    echo "it's a mode!" >&2
	    return 0
	;;
	"") echo "it's empty!" >&2
	    return 0
	;;
	*)
	    echo "it's not a mode!" >&2
	    return 1
	;;
    esac
}


usage() {
 echo "usage: $0 -newcert|-newreq|-newreq-nodes|-newca|-sign|-verify" >&2
}

if [ -f ./openssl.cnf ] 
    then SSLEAY_CONFIG="-config ./openssl.cnf"
    export SSLEAY_CONFIG
    echo "local openssl.cnf file found" 
fi

if [ -z "$OPENSSL" ]; then OPENSSL=openssl; fi

if [ -z "$DAYS" ] ; then DAYS="-days 365" ; fi	# 1 year
CADAYS="-days 1095"	# 3 years
REQ="$OPENSSL req $SSLEAY_CONFIG"
CA="$OPENSSL ca -verbose $SSLEAY_CONFIG"
VERIFY="$OPENSSL verify"
X509="$OPENSSL x509"
PKCS12="openssl pkcs12"

if [ -z "$CATOP" ] ; then CATOP=./ ; fi
CAKEY=./cakey.pem
CAREQ=./careq.pem
CACERT=./cacert.pem

RET=0

while [ "$1" != "" ] ; do
case $1 in
-\?|-h|-help)
    usage
    exit 0
    ;;
-newcert)
    until (is_mode $2) 
    do
	shift
	case $1 in 
	    -bits=*) bits="-newkey rsa:${1#-*=}"
		;;
	    -days=*) days="-days ${1#-*=}"
		;;
	    -extensions=*) reqext="-reqexts ${1#-*=}"
		;;
	    -name=*) fileprefix="${1#-*=}"
		;;
	esac
    done
    # create a certificate
    $REQ -new -x509 -keyout ${fileprefix:-new}key.pem -out ${fileprefix:-new}cert.pem $DAYS $days $bits $reqext
    RET=$?
    echo "Request is in ${fileprefix:-new}cert.pem, private key is in ${fileprefix:-new}key.pem"
    unset bits days reqext fileprefix
    ;;
-newreq|-newreq-nodes)
    if [ "$1" = "-newreq-nodes" ]
    then
	nodesset="-nodes" 
    fi

    until (is_mode $2) 
    do
	shift
	case $1 in 
	    -bits=*) bits="-newkey rsa:${1#-*=}"
		;;
	    -days=*) days="-days ${1#-*=}"
		;;
	    -extensions=*) reqext="-reqexts ${1#-*=}"
		;;
	    -name=*) fileprefix="${1#-*=}"
		;;
	esac
    done
    # create a certificate request
    $REQ -new $nodesset -keyout ${fileprefix:-new}key.pem -out ${fileprefix:-new}req.pem $DAYS $days $bits $reqext
    RET=$?
    echo "Request is in ${fileprefix:-new}req.pem, private key is in ${fileprefix:-new}key.pem"
    unset bits days reqext nodesset fileprefix
    ;;
-newca)
    until (is_mode $2) 
    do
	shift
	case $1 in 
	    -bits=*) bits="-newkey rsa:${1#-*=}"
		;;
	    -days=*) days="-days ${1#-*=}"
		;;
	    -extensions=*) exten="${1#-*=}"
		;;
	esac
    done

    # if explicitly asked for or it doesn't exist then setup the directory
    # structure that Eric likes to manage things
	
    NEW="1"
    if [ "$NEW" -o ! -f ${CATOP}/serial ]; then
	# create the directory hierarchy
	mkdir -p ${CATOP}
	mkdir -p ${CATOP}/certs
	mkdir -p ${CATOP}/crl
	mkdir -p ${CATOP}/newcerts
	mkdir -p ${CATOP}/private
	touch ${CATOP}/index.txt
    fi
    if [ ! -f ${CATOP}/private/$CAKEY ]; then
	echo "CA certificate filename (or enter to create)"
	read FILE

	# ask user for existing CA certificate
	if [ "$FILE" -a -f "$FILE" -a -r "$FILE" ]; then
	    cp_pem $FILE ${CATOP}/private/$CAKEY PRIVATE
	    cp_pem $FILE ${CATOP}/$CACERT CERTIFICATE
	    RET=$?
	    if [ ! -f "${CATOP}/serial" ]; then
		$X509 -in ${CATOP}/$CACERT -noout -next_serial \
		      -out ${CATOP}/serial
	    fi
	else
	    echo "Making CA certificate ..."
	    $REQ -new -keyout ${CATOP}/private/$CAKEY \
			   -out ${CATOP}/$CAREQ $bits
	    RET=$?
	    if [ -s ${CATOP}/private/${CAKEY} ] ; then 
		$CA -create_serial -out ${CATOP}/$CACERT $CADAYS -batch \
			   -keyfile ${CATOP}/private/$CAKEY -selfsign \
			   -extensions ${exten:-v3_ca} \
			   -infiles ${CATOP}/$CAREQ
		RET=$?
	    else
		echo "CA key generation failed." 1>&2 
	    fi	
	fi
    fi
    unset bits days exten
    ;;
-xsign)
    $CA -policy policy_anything -infiles newreq.pem
    RET=$?
    ;;
-pkcs12)
    if [ -z "$2" ] ; then
	CNAME="My Certificate"
    else
	CNAME="$2"
    fi
    $PKCS12 -in newcert.pem -inkey newreq.pem -certfile ${CATOP}/$CACERT \
	    -out newcert.p12 -export -name "$CNAME"
    RET=$?
    exit $RET
    ;;
-sign|-signreq)
    $CA -policy policy_anything -out newcert.pem -infiles newreq.pem
    RET=$?
    cat newcert.pem
    echo "Signed certificate is in newcert.pem"
    ;;
-signCA)
    $CA -policy policy_anything -out newcert.pem -extensions v3_ca -infiles newreq.pem
    RET=$?
    echo "Signed CA certificate is in newcert.pem"
    ;;
-signcert)
    echo "Cert passphrase will be requested twice - bug?"
    $X509 -x509toreq -in newreq.pem -signkey newreq.pem -out tmp.pem
    $CA -policy policy_anything -out newcert.pem -infiles tmp.pem
    RET=$?
    cat newcert.pem
    echo "Signed certificate is in newcert.pem"
    ;;
-verify)
    shift
    if [ -z "$1" ]; then
	    $VERIFY -CAfile $CATOP/$CACERT newcert.pem
	    RET=$?
    else
	for j
	do
	    $VERIFY -CAfile $CATOP/$CACERT $j
	    if [ $? != 0 ]; then
		    RET=$?
	    fi
	done
    fi
    exit $RET
    ;;
-exterminate)
    pushd ${CATOP}
    ls -A | egrep -v '(CA\.sh|openssl\.cnf|\.git)' | xargs rm -rf 
    popd
    ;;
*)
    echo "Command: $0 $*" 
    echo "Unknown arg $1" >&2
    usage
    exit 1
    ;;
esac
shift
done
exit $RET
