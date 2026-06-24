import os

def find_node():
    paths_to_check = [
        "/Users/mac/.nvm",
        "/Users/mac/.node",
        "/Users/mac/.n",
        "/Users/mac/.npm",
        "/usr/local/Cellar",
        "/opt/homebrew"
    ]
    for path in paths_to_check:
        if os.path.exists(path):
            print(f"Exists: {path}")
            # Walk directory to find "node" binary
            for root, dirs, files in os.walk(path):
                if "node" in files:
                    node_path = os.path.join(root, "node")
                    # Check if it's executable
                    if os.access(node_path, os.X_OK) and not os.path.isdir(node_path):
                        print(f"  Found executable node: {node_path}")
                # Limit depth
                depth = root.replace(path, "").count(os.sep)
                if depth > 4:
                    dirs.clear()

if __name__ == "__main__":
    find_node()
