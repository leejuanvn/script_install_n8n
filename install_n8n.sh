#!/bin/bash

# --- Cấu hình Ban đầu ---
# Yêu cầu người dùng nhập thông tin
read -p "Nhập tên miền đầy đủ cho n8n (ví dụ: n8n.yourdomain.com): " N8N_DOMAIN
read -p "Nhập tên cơ sở dữ liệu PostgreSQL (mặc định: n8n_database): " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-n8n_database} # Giá trị mặc định

read -p "Nhập tên người dùng cơ sở dữ liệu PostgreSQL (mặc định: n8n_user): " POSTGRES_USER
POSTGRES_USER=${POSTGRES_USER:-n8n_user} # Giá trị mặc định

# Tạo mật khẩu ngẫu nhiên an toàn cho PostgreSQL
POSTGRES_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16)
echo "Mật khẩu PostgreSQL của bạn sẽ là: $POSTGRES_PASSWORD"
echo "Hãy ghi lại mật khẩu này. Nó cũng sẽ được lưu trong tệp .env"

# Trích xuất SUBDOMAIN và DOMAIN_NAME từ N8N_DOMAIN
# Điều này giúp thiết lập Nginx và các biến môi trường một cách chính xác
SUBDOMAIN=$(echo "$N8N_DOMAIN" | cut -d'.' -f1)
DOMAIN_NAME=$(echo "$N8N_DOMAIN" | sed "s/^$SUBDOMAIN\.//")

# Nếu tên miền không có subdomain rõ ràng (ví dụ: example.com thay vì www.example.com)
if [ "$SUBDOMAIN" = "$DOMAIN_NAME" ]; then
    echo "Cảnh báo: Tên miền bạn nhập không chứa subdomain rõ ràng. Sử dụng tên miền gốc."
    SUBDOMAIN="@" # Ký hiệu cho tên miền gốc trong một số hệ thống DNS
fi

# Múi giờ mặc định (có thể tùy chỉnh)
GENERIC_TIMEZONE="Asia/Ho_Chi_Minh" # Ví dụ: "America/New_York" hoặc "Europe/London"

# Thư mục cài đặt n8n
N8N_DIR="n8n-docker"

echo "Bắt đầu cài đặt n8n cho tên miền: $N8N_DOMAIN"
echo "Thư mục cài đặt: $N8N_DIR (trong thư mục hiện tại của người dùng)"
echo "-----------------------------------"

# --- Hàm kiểm tra và cài đặt Docker & Docker Compose ---
install_docker() {
    if ! command -v docker &> /dev/null
    then
        echo "Docker không được tìm thấy. Đang cài đặt Docker..."
        sudo apt update
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io
        sudo usermod -aG docker "$USER"
        echo "Docker đã được cài đặt. Vui lòng đăng xuất và đăng nhập lại hoặc chạy 'newgrp docker' để áp dụng quyền."
        sleep 5 # Đợi một chút
    else
        echo "Docker đã được cài đặt."
    fi

    if ! command -v docker-compose &> /dev/null
    then
        echo "Docker Compose không được tìm thấy. Đang cài đặt Docker Compose..."
        sudo apt install -y docker-compose
        echo "Docker Compose đã được cài đặt."
    else
        echo "Docker Compose đã được cài đặt."
    fi
}

# --- Bắt đầu quá trình cài đặt ---

# Cài đặt Docker và Docker Compose
install_docker

# Tạo thư mục và di chuyển vào
mkdir -p "$N8N_DIR"
cd "$N8N_DIR" || { echo "Không thể vào thư mục $N8N_DIR. Thoát."; exit 1; }

# --- Tạo tệp .env ---
echo "Tạo tệp .env..."
cat <<EOF > .env
# Cấu hình PostgreSQL
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Cấu hình n8n (ban đầu là HTTP, sẽ được cập nhật thành HTTPS sau khi có SSL)
N8N_PROTOCOL=http
SUBDOMAIN=${SUBDOMAIN}
DOMAIN_NAME=${DOMAIN_NAME}
N8N_HOST=${N8N_DOMAIN}
WEBHOOK_URL=http://${N8N_DOMAIN}/

# Múi giờ
GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
TZ=${GENERIC_TIMEZONE}

# Cần thiết cho CORS nếu dùng tên miền với Nginx
VUE_APP_URL_BASE_API=http://${N8N_DOMAIN}/
EOF

# --- Tạo tệp docker-compose.yml ---
echo "Tạo tệp docker-compose.yml..."
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  n8n:
    image: n8n.io/n8n
    restart: always
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_HOST=${N8N_DOMAIN} # Sẽ được cập nhật sau để phù hợp với SSL
      - WEBHOOK_URL=http://${N8N_DOMAIN}/ # Sẽ được cập nhật sau để phù hợp với SSL
      - N8N_PROTOCOL=http # Sẽ được cập nhật sau để phù hợp với SSL
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${GENERIC_TIMEZONE}
      - VUE_APP_URL_BASE_API=http://${N8N_DOMAIN}/ # Sẽ được cập nhật sau để phù hợp với SSL
    volumes:
      - ./n8n_data:/home/node/.n8n # Lưu trữ dữ liệu n8n (ví dụ: các tệp Binary)
    depends_on:
      - postgres
    networks:
      - n8n_network

  postgres:
    image: postgres:13
    restart: always
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data # Lưu trữ dữ liệu PostgreSQL
    networks:
      - n8n_network

volumes:
  postgres_data: # Định nghĩa Docker volume để lưu trữ dữ liệu PostgreSQL vĩnh viễn
  n8n_data:      # Định nghĩa Docker volume để lưu trữ dữ liệu n8n vĩnh viễn

networks:
  n8n_network:   # Định nghĩa một mạng riêng cho n8n và PostgreSQL để giao tiếp
    driver: bridge
EOF

# --- Khởi động n8n và PostgreSQL lần đầu (HTTP) ---
echo "Khởi động n8n và PostgreSQL lần đầu (chế độ HTTP tạm thời)..."
docker-compose up -d

echo "Đợi n8n khởi động hoàn tất (khoảng 20 giây)..."
sleep 20 # Đợi để các container có thời gian khởi động

# --- Cài đặt và cấu hình Nginx ---
echo "Cài đặt và cấu hình Nginx..."
sudo apt update
sudo apt install -y nginx

# Tạo tệp cấu hình Nginx
NGINX_CONFIG="/etc/nginx/sites-available/$N8N_DOMAIN"
echo "Tạo cấu hình Nginx tại $NGINX_CONFIG"
cat <<EOF | sudo tee "$NGINX_CONFIG" > /dev/null
server {
    listen 80;
    server_name ${N8N_DOMAIN};

    location / {
        proxy_pass http://localhost:5678; # n8n đang chạy trên cổng 5678 trong Docker
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }
}
EOF

# Kích hoạt cấu hình Nginx
echo "Kích hoạt cấu hình Nginx..."
sudo ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# --- Cài đặt Certbot và lấy chứng chỉ SSL ---
echo "Cài đặt Certbot và lấy chứng chỉ SSL từ Let's Encrypt..."
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot

echo "Chạy Certbot để lấy chứng chỉ SSL cho $N8N_DOMAIN..."
# Chạy Certbot để tự động cấu hình Nginx và lấy chứng chỉ
# THAY THẾ 'your_email@example.com' BẰNG ĐỊA CHỈ EMAIL THỰC CỦA BẠN
sudo certbot --nginx -d "$N8N_DOMAIN" --non-interactive --agree-tos --email your_email@example.com

# Kiểm tra gia hạn tự động của Certbot (Certbot sẽ tự động thiết lập cron job/timer)
echo "Kiểm tra trạng thái gia hạn tự động của Certbot..."
sudo systemctl status snap.certbot.renew.service

# --- Cập nhật cấu hình n8n sang HTTPS ---
echo "Cập nhật cấu hình n8n sang HTTPS sau khi có chứng chỉ SSL..."

# Cập nhật tệp .env
sed -i "s|N8N_PROTOCOL=http|N8N_PROTOCOL=https|" .env
sed -i "s|WEBHOOK_URL=http://${N8N_DOMAIN}/|WEBHOOK_URL=https://${N8N_DOMAIN}/|" .env
sed -i "s|VUE_APP_URL_BASE_API=http://${N8N_DOMAIN}/|VUE_APP_URL_BASE_API=https://${N8N_DOMAIN}/|" .env

# Cập nhật tệp docker-compose.yml
# Sử dụng 'sed' với dấu phân cách khác (#) để tránh xung đột với các ký tự trong URL (/)
sed -i "s#N8N_PROTOCOL=http#N8N_PROTOCOL=https#" docker-compose.yml
sed -i "s#WEBHOOK_URL=http:\/\/${N8N_DOMAIN}\/#WEBHOOK_URL=https:\/\/${N8N_DOMAIN}\/#" docker-compose.yml
sed -i "s#VUE_APP_URL_BASE_API=http:\/\/${N8N_DOMAIN}\/#VUE_APP_URL_BASE_API=https:\/\/${N8N_DOMAIN}\/#" docker-compose.yml


# Khởi động lại các container Docker để áp dụng thay đổi cấu hình HTTPS
echo "Khởi động lại các dịch vụ Docker để áp dụng cấu hình HTTPS..."
docker-compose down
docker-compose up -d

# --- Tùy chọn tự động cập nhật n8n ---
read -p "Bạn có muốn thiết lập tự động cập nhật n8n vào lúc 2 giờ sáng mỗi ngày không? (y/n): " AUTO_UPDATE_CHOICE
if [[ "$AUTO_UPDATE_CHOICE" =~ ^[Yy]$ ]]; then
    echo "Thiết lập tự động cập nhật n8n..."
    # Lấy đường dẫn tuyệt đối của thư mục cài đặt n8n
    N8N_ABS_DIR="$(pwd)"

    # Tạo một script cập nhật riêng
    UPDATE_SCRIPT_PATH="/usr/local/bin/update_n8n.sh"
    cat <<EOF | sudo tee "$UPDATE_SCRIPT_PATH" > /dev/null
#!/bin/bash
# Script tự động cập nhật n8n qua Docker Compose

N8N_APP_DIR="${N8N_ABS_DIR}" # Đường dẫn tự động lấy được

echo "\$(date): Bắt đầu cập nhật n8n..."

# Chuyển đến thư mục n8n-docker
cd "\$N8N_APP_DIR" || { echo "\$(date): Lỗi: Không thể vào thư mục \$N8N_APP_DIR. Thoát cập nhật."; exit 1; }

# Kéo ảnh n8n mới nhất và khởi động lại dịch vụ n8n
# 'docker compose pull n8n' chỉ kéo ảnh n8n, 'docker compose up -d n8n' khởi động lại n8n với ảnh mới
/usr/bin/docker-compose pull n8n
/usr/bin/docker-compose up -d n8n

echo "\$(date): Cập nhật n8n hoàn tất."
EOF

    sudo chmod +x "$UPDATE_SCRIPT_PATH"

    # Thêm cron job để chạy script cập nhật vào lúc 2 giờ sáng mỗi ngày
    (sudo crontab -l 2>/dev/null; echo "0 2 * * * ${UPDATE_SCRIPT_PATH} >> /var/log/n8n_update.log 2>&1") | sudo crontab -
    echo "Đã thiết lập cron job để tự động cập nhật n8n vào lúc 2 giờ sáng mỗi ngày."
    echo "Nhật ký cập nhật sẽ được ghi vào: /var/log/n8n_update.log"
else
    echo "Không thiết lập tự động cập nhật n8n."
fi


echo "-----------------------------------"
echo "Quá trình cài đặt n8n đã hoàn tất!"
echo "Bạn có thể truy cập n8n tại: https://$N8N_DOMAIN"
echo "Mật khẩu PostgreSQL của bạn là: $POSTGRES_PASSWORD"
echo "Hãy đảm bảo rằng cổng 80 và 443 đã được mở trên tường lửa của bạn."
echo "Bạn có thể kiểm tra trạng thái các container với: docker-compose ps"
echo "Để dừng n8n: cd $N8N_DIR && docker-compose down"
echo "Để khởi động n8n: cd $N8N_DIR && docker-compose up -d"
echo "-----------------------------------"
