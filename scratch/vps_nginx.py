import paramiko

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"

def run_cmd(cmd):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(hostname, username=username, password=password, timeout=10)
        stdin, stdout, stderr = ssh.exec_command(cmd)
        print(stdout.read().decode('utf-8'))
        print(stderr.read().decode('utf-8'))
    except Exception as e:
        print(f"Error: {e}")
    finally:
        ssh.close()

if __name__ == "__main__":
    print("=== Nginx config file: /etc/nginx/sites-available/alphapos ===")
    run_cmd("cat /etc/nginx/sites-available/alphapos")
