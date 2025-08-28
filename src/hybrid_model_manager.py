import json
import os
import subprocess
from datetime import datetime
from pathlib import Path

class HybridModelManager:
    def __init__(self):
        self.model_dir = Path("model/")
        self.metadata_file = self.model_dir / "model_metadata.json"
        
    def handle_model_update(self, model_path, description=""):
        """Xử lý khi có model mới - trigger Jenkins CI/CD"""
        
        # 1. Cập nhật metadata
        self._update_metadata(model_path, description)
        
        # 2. Commit metadata (không commit model weights)
        self._commit_metadata()
        
        # 3. Tạo version tag
        self._create_version_tag()
        
        # 4. Push tag để trigger Jenkins
        self._push_tag()
        
        print(f"✅ Model update completed! Jenkins CI/CD will be triggered automatically.")
        
    def _update_metadata(self, model_path, description):
        """Cập nhật metadata file"""
        metadata = {
            "model_path": str(model_path),
            "version": self._get_next_version(),
            "description": description,
            "updated_at": datetime.now().isoformat(),
            "file_size": os.path.getsize(model_path),
            "checksum": self._calculate_checksum(model_path),
            "training_data_version": self._get_data_version()
        }
        
        with open(self.metadata_file, 'w') as f:
            json.dump(metadata, f, indent=2)
    
    def _get_next_version(self):
        """Tự động tăng version number"""
        if self.metadata_file.exists():
            with open(self.metadata_file, 'r') as f:
                current = json.load(f)
                current_version = current.get('version', '0.0.0')
                major, minor, patch = map(int, current_version.split('.'))
                return f"{major}.{minor}.{patch + 1}"
        return "1.0.0"
    
    def _calculate_checksum(self, file_path):
        """Tính checksum của file"""
        import hashlib
        hash_md5 = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    
    def _get_data_version(self):
        """Lấy version của training data"""
        data_dir = Path("data/")
        if (data_dir / "data_version.txt").exists():
            with open(data_dir / "data_version.txt", 'r') as f:
                return f.read().strip()
        return "unknown"
    
    def _commit_metadata(self):
        """Commit metadata file"""
        subprocess.run(["git", "add", str(self.metadata_file)], check=True)
        subprocess.run([
            "git", "commit", "-m", 
            f"Update model metadata - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        ], check=True)
        subprocess.run(["git", "push"], check=True)
    
    def _create_version_tag(self):
        """Tạo version tag để trigger Jenkins"""
        with open(self.metadata_file, 'r') as f:
            metadata = json.load(f)
            version = metadata['version']
        
        tag_name = f"model-v{version}"
        subprocess.run(["git", "tag", tag_name], check=True)
    
    def _push_tag(self):
        """Push tag để trigger Jenkins"""
        subprocess.run(["git", "push", "--tags"], check=True)
