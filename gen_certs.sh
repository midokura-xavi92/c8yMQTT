#!/bin/sh
#set -x
set -e

# This procedure implements the instructions at
#   https://cumulocity.com/guides/device-sdk/mqtt/#generating-and-signing-certificates
# without using an intermediate certificate


mkdir -p certs
cd certs

mkdir -p crl
CA_CONF="caConfig.cnf"
CA_KEY="caKey.pem"
CA_CERT="caCert.pem"

mkdir -p deviceCertificates

generate_ca()
(
    touch database.txt
    echo 0001 > serial

    [ -r ${CA_CONF} ] || cat > ${CA_CONF} <<-EOF
	[ ca ]
	default_ca = CA_default
	[ CA_default ]
	# Directory and file locations.
	dir               = ${PWD}
	certs             = \$dir # directory where the CA certificate will be stored.
	crl_dir           = \$dir/crl # directory where the certificate revocation list will be stored.
	new_certs_dir     = \$dir/deviceCertificates # directory where certificates signed by CA certificate will be stored.
	database          = \$dir/database.txt # database file, where the history of the certificates signing operations will be stored.
	serial            = \$dir/serial # directory to the file, which stores next value that will be assigned to signed certificate.

	# The CA key and CA certificate for signing other certificates.
	private_key       = \$dir/caKey.pem # CA private key which will be used for signing certificates.
	certificate       = \$dir/caCert.pem # CA certificate, which will be the issuer of signed certificate.

	default_md        = sha256 # hash function
	default_days      = 375 # default number of days for which the certificate will be valid since the date of its generation.
	preserve          = no # if set to 'no' then it will determine the same order of the distinguished name in every signed certificate.
	policy            = signing_policy # the name of the tag in this file that specifies the fields of the certificate. The fields have to be filled in or even match the CA certificate values to be signed.

	# For certificate revocation lists.
	crl               = \$crl_dir/caCrl.pem # CA certificate revocation list
	crlnumber         = \$crl_dir/crlnumber # serial, but for the certificate revocation list
	crl_extensions    = crl_ext # the name of the tag in this file, which specifies certificates revocation list extensions, which will be added to the certificate revocation by default.
	default_crl_days  = 30 # default number of days for which the certificate revocation list will be valid since the date of its generation. After that date it should be updated to see if there are new entries on the list.

	[ req ]
	default_bits        = 4096 # default key size in bits.
	distinguished_name  = req_distinguished_name # the name of the tag in this file, which specifies certificates fields description during certificate creation and eventually set some default values.
	string_mask         = utf8only # permitted string type mask.
	default_md          = sha256 # hash function.
	x509_extensions     = v3_ca # the name of the tag in this file, which specifies certificates extensions, which will be added to the created certificate by default.

	# descriptions and default values of the created certificate fields.
	[ req_distinguished_name ]
	countryName                     = ES
	stateOrProvinceName             = Spain
	localityName                    = Barcelona
	organizationName                = Midokura
	organizationalUnitName          = Device Team
	commonName                      = identifierName
	emailAddress                    = test@midokura.com

	# A default value for each field can be set by adding an extra line with field name and postfix "_default". For example: "countryName_default = PL". If you add this line here, then leaving country name empty during certificate creation will result in the value "PL" being used. If the default value was specified there, but during certificate creation you do not want to use this value, then instead use "." as the value. It will leave the value empty and not use the default.

	# default extensions for the CA certificate.
	[ v3_ca ]
	subjectKeyIdentifier = hash # subject key value will be calculated using hash funtion. It's the recommended setting by PKIX.
	authorityKeyIdentifier = keyid:always,issuer # The subject key identifier will be copied from the parent certificate. It's the recommended setting by PKIX.
	basicConstraints = critical, CA:true, pathlen:10 # "critical" specifies that the extension is important and has to be read by the platform. CA says if it is the CA certificate so it can be used to sign different certificates. "pathlen" specifies the maximum path length between this certificate and the device certificate in the chain of certificates during authentication. Path length is set here only to show how it is done. If you do not want to specify max path length, you can keep only the "basicConstraints = critical, CA:true" part here.
	keyUsage = digitalSignature, cRLSign, keyCertSign # specifies permitted key usages.

	# Default extensions for the device certificate. This tag is not used directly anywhere in this file, but will be used from the command line to create signed certificate with "-extensions v3_signed" parameter.
	[ v3_signed ]
	subjectKeyIdentifier = hash
	authorityKeyIdentifier = keyid,issuer
	basicConstraints = critical, CA:false
	keyUsage = nonRepudiation, digitalSignature, keyEncipherment

	# default extensions for certificate revocation list
	[ crl_ext ]
	authorityKeyIdentifier=keyid:always

	# Policy of certificates signing. It specifies which certificate fields have to be filled in during certificate creation. There are three possible values here:
	# "optional" - field value can be empty
	# "supplied" - field value must be filled in
	# "match" - signed certificate field value must match the CA certificate value to be created
	[ signing_policy ]
	countryName             = optional
	stateOrProvinceName     = optional
	organizationName        = optional
	organizationalUnitName  = optional
	commonName              = optional # or 'supplied' every certificate should have a unique common name, so this value should not be changed.
	emailAddress            = optional
	EOF

    # Create the CA key
    [ -r ${CA_KEY} ] || generate_key_nopass ${CA_KEY}   # openssl genrsa -aes256 -out ${CA_KEY} 4096

    # Create the CA certificate
    [ -r ${CA_CERT} ] || openssl req -config ${CA_CONF} -key ${CA_KEY} -new -days 7300 \
                -x509 -sha256 -extensions v3_ca \
                -out ${CA_CERT}

    # Print the generated CA certificate
    openssl x509 -noout -text -in ${CA_CERT}
)

generate_client_pair()
(
    set -u
    local identifier=$1

    echo
    echo "Enter '${identifier}' as the common name at the CSR generation step"
    echo

    CLIENT_KEY="deviceCertificates/device_${identifier}.key.pem"
    [ -r "${CLIENT_KEY}" ] || generate_key_nopass "${CLIENT_KEY}"

    CLIENT_CSR="deviceCertificates/device_${identifier}.csr"
    [ -r "${CLIENT_CSR}" ] || openssl req -config ${CA_CONF} -new -sha256 -key "${CLIENT_KEY}" -out "${CLIENT_CSR}"

    CLIENT_CERT="deviceCertificates/device_${identifier}.crt.pem"
    [ -r "${CLIENT_CERT}" ] || openssl ca -config ${CA_CONF} -extensions v3_signed \
                    -days 365 -notext -md sha256 \
                    -in "${CLIENT_CSR}" \
                    -out "${CLIENT_CERT}"

    # Verify correct signing by CA
    openssl verify -partial_chain -CAfile ${CA_CERT} "${CLIENT_CERT}"

    # Create certificate chain
    CLIENT_CHAIN="deviceCertificates/device_${identifier}.chain.pem"
    [ -r "${CLIENT_CHAIN}" ] || cat "${CLIENT_CERT}" ${CA_CERT} > "${CLIENT_CHAIN}"

    echo
    echo "Created:"
    ls -1 "${CLIENT_CERT}" "${CLIENT_KEY}" "${CLIENT_CHAIN}"
)

generate_key_nopass()
(
    set -u

    local key_out=$1
    local bogus_passphrase="bogus"

    openssl genrsa -aes256 \
            -passout pass:${bogus_passphrase} \
            4096 | \
        openssl rsa \
            -passin pass:${bogus_passphrase} -out "${key_out}"
    return $?
)


[ -r caCert.pem ] || generate_ca

[ -z $1 ] || generate_client_pair $1
