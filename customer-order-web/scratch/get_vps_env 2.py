import paramiko

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"

def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(hostname, username=username, password=password, timeout=15)
        # Find all .env files on the VPS
        stdin, stdout, stderr = ssh.exec_command("find / -name '.env' -not -path '*/venv/*' -not -path '*/node_modules/*' 2>/dev/null")
        env_files = stdout.read().decode().strip().split('\n')
        print("Found .env files:")
        for f in env_files:
            print(f"  {f}")
            
        # Also check where docker-compose is running or let's list files in /root or /opt
        stdin, stdout, stderr = ssh.exec_command("ls -la /root")
        print("\nFiles in /root:")
        print(stdout.read().decode())
        
        # Let's inspect the first .env file found
        for f in env_files:
            if 'supabase' in f or 'AlphaPos' in f or 'docker' in f:
                print(f"\nContent of {f}:")
                stdin, stdout, stderr = ssh.exec_command(f"cat {f}")
                print(stdout.read().decode())
                break
    except Exception as e:
        print("Error:", e)
    finally:
        ssh.close()

if __name__ == "__main__":
    main()
