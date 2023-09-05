# 配置环境
npm install -g hexo-cli
npm install
hexo generate
rm -rf /etc/nginx/page/*
cp public/* /etc/nginx/page 
