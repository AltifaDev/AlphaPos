import paramiko

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"

def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(hostname, username=username, password=password, timeout=15)
        stdin, stdout, stderr = ssh.exec_command("docker port supabase_db_AlphaPos")
        print("Database Ports:")
        print(stdout.read().decode())
        
        stdin, stdout, stderr = ssh.exec_command("docker ps --filter name=db")
        print("Database container status:")
        print(stdout.read().decode())
    except Exception as e:
        print("Error:", e)
    finally:
        ssh.close()

if __name__ == "__main__":
    main()
