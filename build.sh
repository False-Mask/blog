# 配置环境
npm install -g hexo-cli
npm install
hexo generate
rm -rf /etc/nginx/page/*
cp /var/jenkins_home/* /etc/nginx/page 
