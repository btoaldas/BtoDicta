#!/bin/bash
# Crea un certificado de firma propio "BetoDicta Self Signed" en tu llavero.
# OPCIONAL: solo si quieres que los permisos de macOS (micrófono, accesibilidad…)
# se conserven entre recompilaciones. Sin esto, la app se firma "ad-hoc" y
# funciona igual, pero macOS pedirá los permisos de nuevo tras cada `make install`.
# El certificado es TUYO y personal — se queda en tu llavero, nunca se comparte.
set -e
NAME="BetoDicta Self Signed"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Ya tienes el certificado '$NAME'. Nada que hacer."
  exit 0
fi
TMP=$(mktemp -d)
cat > "$TMP/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $NAME
[ v3 ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes -config "$TMP/cert.conf"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
  -passout pass:btodicta -name "$NAME" -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P "btodicta" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true
rm -rf "$TMP"
echo "Listo. '$NAME' creado. Ahora 'make install' firmará con él y los permisos persistirán."
