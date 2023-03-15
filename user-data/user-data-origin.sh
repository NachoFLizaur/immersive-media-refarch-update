#!/bin/bash

INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

yum -y --security update

yum -y update aws-cli

yum -y install \
  awslogs jq htop pcre-devel zlib-devel \
  openssl-devel gcc gcc-c++ make libaio \
  libaio-devel openssl libxslt-devel rpm-build \
  gperftools-devel GeoIP-devel gd-devel perl-devel perl-ExtUtils-Embed

yum -y --enablerepo=epel install mediainfo
# amazon-linux-extras install epel -y
# yum -y install mediainfo

aws configure set default.region $REGION

aws ec2 attach-network-interface --network-interface-id $ENI_ID --instance-id $INSTANCE_ID --device-index 1

cd /tmp && \
  curl -kO https://www.johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz && \
  tar Jxf ffmpeg-git-amd64-static.tar.xz && \
  cp -av ffmpeg*/{ff*,qt*} /usr/local/bin

cd /tmp && \
  git clone https://github.com/arut/nginx-rtmp-module

# ! Old way of rebuilding nginx w/ the RTMP module

# yum -y install \
#   nginx && \
#   yes | get_reference_source -p nginx && \
#   yum -y remove nginx && \
#   rpm -Uvh /usr/src/srpm/debug/nginx*.rpm

# curl https://nginx.org/packages/rhel/7/x86_64/RPMS/nginx-1.18.0-1.el7.ngx.x86_64.rpm --output nginx-1.18.0-1.el7.ngx.x86_64.rpm

# sed -i "s|configure|configure --add-module=/tmp/nginx-rtmp-module|" /rpmbuild/SPECS/nginx.spec

# rpmbuild -ba /rpmbuild/SPECS/nginx.spec

# rpm -Uvh /rpmbuild/RPMS/x86_64/nginx*.rpm

# cp -av /tmp/nginx-rtmp-module/stat.xsl /usr/share/nginx/html

# ! ##############################################

# ? New way of rebuilding nginx w/ the RTMP module

# yum -y install nginx

yum install git gcc make pcre-devel openssl-devel zlib1g-dev

mkdir ~/build && cd ~/build

git clone https://github.com/arut/nginx-rtmp-module

wget http://nginx.org/download/nginx-1.20.1.tar.gz
tar xzf nginx-1.20.1.tar.gz
cd nginx-1.20.1

./configure --with-http_ssl_module --add-module=../nginx-rtmp-module --prefix=/etc/nginx --sbin-path=/usr/sbin/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log
make
make install

# ? ##############################################

mkdir /usr/local/nginx/conf/rtmp.d
mkdir /usr/local/nginx/conf/default.d

mkdir -p /var/lib/nginx/{rec,hls,s3}

chown -R nginx. /var/lib/nginx/

echo '$SystemLogRateLimitInterval 2' >> /etc/rsyslog.conf
echo '$SystemLogRateLimitBurst 500' >> /etc/rsyslog.conf

echo "include /usr/local/nginx/conf/rtmp.d/*.conf;" >> /usr/local/nginx/conf/nginx.conf

sed -i "s|worker_processes auto|worker_processes 1|g" /usr/local/nginx/conf/nginx.conf

cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/nginx/default.d/rtmp.conf /usr/local/nginx/conf/default.d/
cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/nginx/rtmp.d/rtmp.conf /usr/local/nginx/conf/rtmp.d/
cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/awslogs/awslogs.conf /etc/awslogs/
cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/bin/record-postprocess.sh /usr/local/bin/
cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/init/spot-instance-termination-notice-handler.conf /etc/init/spot-instance-termination-notice-handler.conf
cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/bin/spot-instance-termination-notice-handler.sh /usr/local/bin/

chmod +x /usr/local/bin/spot-instance-termination-notice-handler.sh

sed -i "s|%INGRESSBUCKET%|$INGRESSBUCKET|g" /usr/local/bin/record-postprocess.sh
chmod +x /usr/local/bin/record-postprocess.sh

sed -i "s|us-east-1|$REGION|g" /etc/awslogs/awscli.conf
sed -i "s|%CLOUDWATCHLOGSGROUP%|$CLOUDWATCHLOGSGROUP|g" /etc/awslogs/awslogs.conf

chkconfig rsyslog on && service rsyslog restart
chkconfig awslogs on && service awslogs restart
chkconfig /usr/local/nginx/sbin/nginx on && service nginx restart

start spot-instance-termination-notice-handler

aws ec2 associate-address --allow-reassociation \
  --allocation-id $ALLOCATION_ID --network-interface-id $ENI_ID

/opt/aws/bin/cfn-signal -s true -i $INSTANCE_ID "$WAITCONDITIONHANDLE"
