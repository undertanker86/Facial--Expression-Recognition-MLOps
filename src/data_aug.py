import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import confusion_matrix, classification_report
from tqdm import tqdm
from PIL import Image
import cv2
from pathlib import Path
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
import os

# Define emotion mapping
EMOTION_MAPPING = {
    1: 'surprise',
    2: 'fear',
    3: 'disgust',
    4: 'happiness',
    5: 'sadness',
    6: 'anger',
    7: 'neutral'
}
        


# Configuration
DATA_PATH = '/kaggle/working/Heatmaps_RafDb_MP_DLIB_sigma_15' 
BATCH_SIZE = 128
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
TARGET_SIZE = (224, 224)  # Size for landmark detection

class FERPlusDataset(Dataset):
    """
    Dataset class for FERPlus dataset with pre-divided train/val/test splits
    """
    def __init__(self, root_dir, split='train', image_size=(224, 224), transform_type=None):
        self.root_dir = Path(root_dir)
        self.split = split
        self.image_size = image_size
        self.transform_type = transform_type
        
        self.global_mean = [0.485, 0.456, 0.406]
        self.global_std = [0.229, 0.224, 0.225]

        
        # Prepare dataset
        self.images, self.labels, self.heat_images = self._load_dataset()
        
        # Print dataset statistics
        self._print_statistics()
        
        # Prepare transforms
        self.base_transform = transforms.Compose([
            transforms.ToPILImage(),
            transforms.Resize(self.image_size),
            transforms.ToTensor(),
        ])
        self.image_transform = transforms.Compose([
                self.base_transform,
                transforms.Normalize(mean=self.global_mean, std=self.global_std)
        ])
        
        
        # Additional train transforms
        self.train_transform = transforms.Compose([
            transforms.RandomHorizontalFlip(p=0.5),
            transforms.RandomRotation(10)
        ])
    
    def _load_dataset(self):
        """Load dataset from preprocessed .npz file"""
        saved_data_path = os.path.join(self.root_dir, f'{self.split}.npz')
        
        try:
            data = np.load(saved_data_path)
            return data['images'], data['labels'], data['heatmaps']
        except Exception as e:
            print(f"Error loading dataset: {e}")
            return [], [], []
    
    def _print_statistics(self):
        """Print dataset statistics"""
        unique_labels, counts = np.unique(self.labels, return_counts=True)
        total_images = len(self.labels)
        
        print(f"\n{self.split} set statistics:")
        print(f"Total images: {total_images}")
        
        for label, count in zip(unique_labels, counts):
            emotion = EMOTION_MAPPING[label]
            percentage = (count / total_images) * 100
            print(f"{emotion}: {count} images ({percentage:.2f}%)")
    

    def __len__(self):
        return len(self.images)
    
    def __getitem__(self, idx):
        # Load image, label, and heatmap
        image = self.images[idx]
        # print(" ảnh gốc:", image.shape)  #  100x100x3
        label = self.labels[idx] - 1
        
        # Transform image
        transformed_image = self.image_transform(image)
        # print("ảnh sau biến đổi:", transformed_image.shape)  # 3x224x224
        
        if self.transform_type == 'train':
            transformed_image = self.train_transform(transformed_image)
    
        
        return transformed_image, label