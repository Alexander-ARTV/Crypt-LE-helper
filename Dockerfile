FROM alpine:latest
LABEL vendor="Crypt::LE"

RUN apk update && apk upgrade && apk add --no-cache \
make \
gcc \
perl \
openssl-dev \
git \
perl-convert-asn1 \
perl-crypt-openssl-bignum \
perl-crypt-openssl-rsa \
perl-io-socket-ssl \
perl-json-maybexs \
perl-log-log4perl \
perl-net-ssleay

RUN git clone https://github.com/Alexander-ARTV/Crypt-LE.git
RUN cd Crypt-LE && \
git checkout resume && \
sed -i 's/ca_list() == 5/ca_list() == 6/' ./t/03-utils.t && \
perl Makefile.PL && \
make && \
make test && \
make install && \
apk del git make gcc && \
rm -r /Crypt-LE

RUN adduser -S -h /data ssl
ENV LC_ALL=en_US.UTF-8
VOLUME /data
WORKDIR /data
USER ssl
ENTRYPOINT ["le.pl"]