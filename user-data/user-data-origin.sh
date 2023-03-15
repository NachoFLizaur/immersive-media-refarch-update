#!/bin/bash

INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

sudo yum -y --security update

sudo yum -y update aws-cli

sudo yum -y install \
  awslogs jq htop pcre-devel zlib-devel \
  openssl-devel gcc gcc-c++ make libaio \
  libaio-devel openssl libxslt-devel rpm-build \
  gperftools-devel GeoIP-devel gd-devel perl-devel perl-ExtUtils-Embed

sudo yum -y --enablerepo=epel install mediainfo
# sudo amazon-linux-extras install epel -y
# sudo yum -y install mediainfo

sudo aws configure set default.region $REGION

sudo aws ec2 attach-network-interface --network-interface-id $ENI_ID --instance-id $INSTANCE_ID --device-index 1

cd /tmp && \
  sudo curl -kO https://www.johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz && \
  sudo tar Jxf ffmpeg-git-amd64-static.tar.xz && \
  sudo cp -av ffmpeg*/{ff*,qt*} /usr/local/bin

cd /tmp && \
  sudo git clone https://github.com/arut/nginx-rtmp-module

# ! Old way of rebuilding nginx w/ the RTMP module

# sudo yum -y install \
#   nginx && \
#   yes | get_reference_source -p nginx && \
#   sudo yum -y remove nginx && \
#   rpm -Uvh /usr/src/srpm/debug/nginx*.rpm

  # sudo curl https://nginx.org/packages/rhel/7/x86_64/RPMS/nginx-1.18.0-1.el7.ngx.x86_64.rpm --output nginx-1.18.0-1.el7.ngx.x86_64.rpm

# sudo sed -i "s|configure|configure --add-module=/tmp/nginx-rtmp-module|" /rpmbuild/SPECS/nginx.spec

# sudo rpmbuild -ba /rpmbuild/SPECS/nginx.spec

# sudo rpm -Uvh /rpmbuild/RPMS/x86_64/nginx*.rpm

# sudo cp -av /tmp/nginx-rtmp-module/stat.xsl /usr/share/nginx/html

# ! ##############################################

# ? New way of rebuilding nginx w/ the RTMP module

sudo yum -y install nginx

sudo yum install git gcc make pcre-devel openssl-devel zlib1g-dev

sudo mkdir ~/build && cd ~/build

sudo git clone https://github.com/arut/nginx-rtmp-module

sudo wget http://nginx.org/download/nginx-1.18.0.tar.gz
sudo tar xzf nginx-1.18.0.tar.gz
cd nginx-1.18.0

sudo ./configure --with-http_ssl_module --add-module=../nginx-rtmp-module
sudo make
sudo make install

# ? ##############################################

sudo mkdir /etc/nginx/rtmp.d

sudo mkdir -p /var/lib/nginx/{rec,hls,s3}

sudo chown -R nginx. /var/lib/nginx/

sudo echo '$SystemLogRateLimitInterval 2' >> /etc/rsyslog.conf
sudo echo '$SystemLogRateLimitBurst 500' >> /etc/rsyslog.conf

sudo echo "include /etc/nginx/rtmp.d/*.conf;" >> /etc/nginx/nginx.conf

sudo sed -i "s|worker_processes auto|worker_processes 1|g" /etc/nginx/nginx.conf

sudo cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/nginx/default.d/rtmp.conf /etc/nginx/default.d/
sudo cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/nginx/rtmp.d/rtmp.conf /etc/nginx/rtmp.d/
sudo cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/awslogs/awslogs.conf /etc/awslogs/
sudo cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/bin/record-postprocess.sh /usr/local/bin/
sudo cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/init/spot-instance-termination-notice-handler.conf /etc/init/spot-instance-termination-notice-handler.conf
sudo cp -av /home/ec2-user/immersive-media-refarch/user-data/origin/bin/spot-instance-termination-notice-handler.sh /usr/local/bin/

sudo chmod +x /usr/local/bin/spot-instance-termination-notice-handler.sh

sudo sed -i "s|%INGRESSBUCKET%|$INGRESSBUCKET|g" /usr/local/bin/record-postprocess.sh
sudo chmod +x /usr/local/bin/record-postprocess.sh

sudo sed -i "s|us-east-1|$REGION|g" /etc/awslogs/awscli.conf
sudo sed -i "s|%CLOUDWATCHLOGSGROUP%|$CLOUDWATCHLOGSGROUP|g" /etc/awslogs/awslogs.conf

sudo chkconfig rsyslog on && service rsyslog restart
sudo chkconfig awslogs on && service awslogs restart
sudo chkconfig nginx on && service nginx restart

sudo start spot-instance-termination-notice-handler

sudo aws ec2 associate-address --allow-reassociation \
  --allocation-id $ALLOCATION_ID --network-interface-id $ENI_ID

sudo /opt/aws/bin/cfn-signal -s true -i $INSTANCE_ID "$WAITCONDITIONHANDLE"
