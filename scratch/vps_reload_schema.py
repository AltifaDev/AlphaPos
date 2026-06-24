import paramiko
import time

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"

JWT_SECRET = "super-secret-jwt-token-with-at-least-32-characters-long"

def make_anon_token():
    import jwt as pyjwt
    payload = {
        "role": "anon",
        "iss": "supabase",
        "iat": int(time.time()),
        "exp": int(time.time()) + 3600
    }
    return pyjwt.encode(payload, JWT_SECRET, algorithm="HS256")

def run():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(hostname, username=username, password=password, timeout=10)

        token = make_anon_token()
        print(f"Anon token: {token[:60]}...")

        # Kong is on port 54321 - try via that
        print("\n=== REST via Kong port 54321 ===")
        stdin, stdout, stderr = ssh.exec_command(
            f"curl -s 'http://localhost:54321/rest/v1/restaurant_tables?select=table_number,is_round,zone&limit=2' "
            f"-H 'apikey: {token}' "
            f"-H 'Authorization: Bearer {token}' 2>&1"
        )
        print(stdout.read().decode()[:500])

        # Check REST container health and get its internal IP
        print("\n=== REST container status ===")
        stdin, stdout, stderr = ssh.exec_command("docker inspect supabase_rest_AlphaPos --format '{{.State.Status}} {{.NetworkSettings.Networks}}'")
        print(stdout.read().decode()[:300])

        # Get REST container's internal port
        stdin, stdout, stderr = ssh.exec_command("docker port supabase_rest_AlphaPos")
        print("REST ports:", stdout.read().decode())

        # Find the REST container's internal IP and connect directly
        stdin, stdout, stderr = ssh.exec_command("docker inspect supabase_rest_AlphaPos --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'")
        rest_ip = stdout.read().decode().strip()
        print(f"REST internal IP: {rest_ip}")

        if rest_ip:
            stdin, stdout, stderr = ssh.exec_command(
                f"curl -s 'http://{rest_ip}:3000/restaurant_tables?select=table_number,is_round,zone&limit=2' "
                f"-H 'Authorization: Bearer {token}' 2>&1"
            )
            print("REST via internal IP:", stdout.read().decode()[:500])

    except Exception as e:
        import traceback
        traceback.print_exc()
    finally:
        ssh.close()

if __name__ == "__main__":
    run()
