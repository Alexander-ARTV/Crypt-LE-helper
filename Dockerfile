FROM alpine:latest
LABEL vendor="Crypt::LE"

RUN apk update && apk upgrade && apk add --no-cache \
make \
gcc \
perl \
openssl-dev \
git \
perl-app-cpanminus \
perl-convert-asn1 \
perl-crypt-openssl-bignum \
perl-crypt-openssl-rsa \
perl-io-socket-ssl \
perl-json-maybexs \
perl-log-dispatch \
perl-log-log4perl \
perl-net-ssleay && \
git clone https://github.com/Alexander-ARTV/Crypt-LE.git && \
cd Crypt-LE && \
git checkout resume && \
sed -i 's/ca_list() == 5/ca_list() == 6/' ./t/03-utils.t && \
perl Makefile.PL && \
make && \
make test && \
make install && \
rm -r /Crypt-LE && \
cd / && \
cpanm Log::Dispatch::FileRotate && \
apk del git make gcc perl-app-cpanminus

RUN adduser -S -h /data ssl
ENV LC_ALL=en_US.UTF-8
VOLUME /data
WORKDIR /data
USER ssl
ENTRYPOINT ["le.pl"]