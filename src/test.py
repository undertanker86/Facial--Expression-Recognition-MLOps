save_path = "./model/outputs/confusion_matrix.png"

EMOTION_MAPPING = {
    1: 'surprise',
    2: 'fear',
    3: 'disgust',
    4: 'happiness',
    5: 'sadness',
    6: 'anger',
    7: 'neutral'
}
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler
import torchvision.transforms as transforms
import torchvision.models as models
from pathlib import Path
import numpy as np
import pandas as pd
import cv2
import os
import random
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
import albumentations as A
from albumentations.pytorch import ToTensorV2
from collections import Counter
from tqdm import tqdm
from efficientfacenet import efficient_face
from data_aug import FERPlusDataset
from torch.utils.data import DataLoader
BATCH_SIZE = 128
DATA_PATH = './Heatmaps_RafDb_MP_DLIB_sigma_15'
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
MODEL_SAVE_PATH = './model/best_model_now.pth'
test_dataset = FERPlusDataset(DATA_PATH, split='test')
test_loader = DataLoader(test_dataset, batch_size=BATCH_SIZE, num_workers=4)



def test_model(model, test_loader, device, model_path=MODEL_SAVE_PATH):
    """Evaluate model on test set (prints loss and accuracy, no return)"""
    # Load best model
    model.load_state_dict(torch.load(model_path, map_location=device))
    model.to(device)
    model.eval()

    all_preds = []
    all_labels = []
    total_loss = 0.0
    criterion = nn.CrossEntropyLoss()

    with torch.no_grad():
        correct = 0
        total = 0

        for inputs, labels in tqdm(test_loader, desc='Testing'):
            inputs, labels = inputs.to(device), labels.to(device)

            outputs = model(inputs)

            loss = criterion(outputs, labels)
            total_loss += loss.item()

            _, predicted = outputs.max(1)
            all_preds.extend(predicted.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())

            correct += (predicted == labels).sum().item()
            total += labels.size(0)
    all_labels = [label + 1 for label in all_labels]
    all_preds = [pred + 1 for pred in all_preds]
    # Compute metrics
    test_loss = total_loss / len(test_loader)
    test_accuracy = 100. * correct / total

    # Print results
    print(f"\nTest Loss: {test_loss:.4f}")
    print(f"Test Accuracy: {test_accuracy:.2f}%")

    # Confusion matrix
    cm = confusion_matrix(all_labels, all_preds)
    cm_percentage = cm.astype('float') / cm.sum(axis=1)[:, np.newaxis] * 100

    # Plot confusion matrix
    plt.figure(figsize=(10, 8))
    sns.heatmap(
        cm_percentage,
        annot=True,
        fmt='.2f',
        cmap='Blues',
        xticklabels=list(EMOTION_MAPPING.values()),
        yticklabels=list(EMOTION_MAPPING.values())
    )
    plt.title('Confusion Matrix (%)')
    plt.ylabel('True Label')
    plt.xlabel('Predicted Label')

    # Save the figure
    plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Confusion matrix saved at: {save_path}")

    # Print classification report
    print("\nClassification Report:")
    print(classification_report(
        all_labels,
        all_preds,
        target_names=list(EMOTION_MAPPING.values()),
        digits=4
    ))


# Create model
print("\nCreating model...")
model = efficient_face()

# Test model
print("\nEvaluating model on test set...")
test_model(model, test_loader, DEVICE, MODEL_SAVE_PATH)