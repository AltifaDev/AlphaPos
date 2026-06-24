import paramiko
import time

hostname = "119.59.99.163"
username = "root"
password = "ZG8&HhiE!kdzcU"
JWT_SECRET = "super-secret-jwt-token-with-at-least-32-characters-long"
MERCHANT_ID = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"

def make_token(role="anon"):
    import jwt as pyjwt
    payload = {"role": role, "iss": "supabase", "iat": int(time.time()), "exp": int(time.time()) + 3600}
    return pyjwt.encode(payload, JWT_SECRET, algorithm="HS256")

def run():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(hostname, username=username, password=password, timeout=10)

        # 1. Check floor_plan_images table
        print("=== floor_plan_images rows ===")
        cmd = f"docker exec supabase_db_AlphaPos psql -U postgres -d postgres -c \"SELECT id, floor, image_filename, is_deleted, scale, offset_x, offset_y FROM public.floor_plan_images WHERE merchant_id='{MERCHANT_ID}';\""
        stdin, stdout, stderr = ssh.exec_command(cmd)
        print(stdout.read().decode())
        print(stderr.read().decode())

        # 2. Check columns exist
        print("=== floor_plan_images schema ===")
        cmd2 = "docker exec supabase_db_AlphaPos psql -U postgres -d postgres -c \"SELECT column_name, data_type FROM information_schema.columns WHERE table_name='floor_plan_images' ORDER BY ordinal_position;\""
        stdin, stdout, stderr = ssh.exec_command(cmd2)
        print(stdout.read().decode())

        # 3. Check storage objects
        print("=== Storage objects for floor_plans ===")
        cmd3 = f"docker exec supabase_db_AlphaPos psql -U postgres -d postgres -c \"SELECT name, bucket_id FROM storage.objects WHERE bucket_id='product-media' AND name LIKE '%floor_plan%' LIMIT 10;\""
        stdin, stdout, stderr = ssh.exec_command(cmd3)
        print(stdout.read().decode())
        print(stderr.read().decode())

        # 4. Try REST API call
        token = make_token("anon")
        print("=== REST API call for floor_plan_images ===")
        cmd4 = (
            f"curl -s 'http://localhost:54321/rest/v1/floor_plan_images"
            f"?merchant_id=eq.{MERCHANT_ID}&is_deleted=eq.false' "
            f"-H 'apikey: {token}' "
            f"-H 'Authorization: Bearer {token}'"
        )
        stdin, stdout, stderr = ssh.exec_command(cmd4)
        print(stdout.read().decode())

    except Exception as e:
        import traceback
        traceback.print_exc()
    finally:
        ssh.close()

if __name__ == "__main__":
    run()
