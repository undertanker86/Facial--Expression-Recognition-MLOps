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
import matplotlib.pyplot as plt
from tqdm import tqdm
from efficientfacenet import EfficientFace
from data_aug import FERPlusDataset
from hybrid_model_manager import HybridModelManager
BATCH_SIZE = 128
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
NUM_EPOCHS = 1
MODEL_SAVE_PATH = './model/outputs/best_model.pth'
DATA_PATH = './Heatmaps_RafDb_MP_DLIB_sigma_15'


train_dataset = FERPlusDataset(DATA_PATH, split='train_split', transform_type='train')
val_dataset = FERPlusDataset(DATA_PATH, split='val')


train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True, num_workers=4)
val_loader = DataLoader(val_dataset, batch_size=BATCH_SIZE, num_workers=4)

def train_model(model, train_loader, val_loader, device, num_epochs=50, model_save_path='models/fer_model.pth'):
    """Train the model"""
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    # Learning rate scheduler
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', patience=5, factor=0.1)
    # scaler = GradScaler()

    best_val_loss = float('inf')
    best_val_acc = 0.0
    train_losses = []
    val_losses = []
    train_accs = []
    val_accs = []

    for epoch in range(num_epochs):
        # Training phase
        model.train()
        running_loss = 0.0
        correct = 0
        total = 0

        pbar = tqdm(train_loader, desc=f'Epoch {epoch+1}/{num_epochs}')
        for inputs, labels  in pbar:
            inputs, labels = inputs.to(device), labels.to(device)
            optimizer.zero_grad()
            outputs = model(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
            _, predicted = outputs.max(1)
            total += labels.size(0)
            correct += predicted.eq(labels).sum().item()

            pbar.set_postfix({'loss': running_loss/len(train_loader), 'acc': 100.*correct/total})

        train_loss = running_loss/len(train_loader)
        train_acc = 100.*correct/total
        train_losses.append(train_loss)
        train_accs.append(train_acc)

        # Validation phase
        model.eval()
        val_loss = 0.0
        correct = 0
        total = 0

        with torch.no_grad():
            for inputs, labels in val_loader:
                inputs, labels = inputs.to(device), labels.to(device)
                outputs = model(inputs)
                loss = criterion(outputs, labels)

                val_loss += loss.item()
                _, predicted = outputs.max(1)
                total += labels.size(0)
                correct += predicted.eq(labels).sum().item()

        val_loss = val_loss/len(val_loader)
        val_acc = 100.*correct/total
        val_losses.append(val_loss)
        val_accs.append(val_acc)

        print(f'Epoch {epoch+1}/{num_epochs}:')
        print(f'Train Loss: {train_loss:.4f}, Train Acc: {train_acc:.2f}%')
        print(f'Val Loss: {val_loss:.4f}, Val Acc: {val_acc:.2f}%')

        # Learning rate scheduling
        scheduler.step(val_loss)

        # Save best model based on validation accuracy
        if val_acc > best_val_acc:
            print('The model which has the best validation accuracy is saved...')
            best_val_acc = val_acc
            print(f'Best Epoch {epoch+1}/{num_epochs}:')
            print("Best Validation Accuracy: ", best_val_acc)
            best_val_acc = val_acc
            torch.save(model.module.state_dict(), model_save_path)

    # Plot training history
    plot_training_history(train_losses, val_losses, train_accs, val_accs)

    return model
import matplotlib.pyplot as plt

def plot_training_history(train_losses, val_losses, train_accs, val_accs):
    """Plot training and validation metrics and save figures separately."""

    # Define save paths
    loss_plot_path = "./model/outputs/loss_plot.png"
    accuracy_plot_path = "./model/outputs/accuracy_plot.png"

    # Plot and save loss separately
    plt.figure(figsize=(8, 5))
    plt.plot(train_losses, label='Train Loss')
    plt.plot(val_losses, label='Val Loss')
    plt.title('Model Loss')
    plt.xlabel('Epoch')
    plt.ylabel('Loss')
    plt.legend()
    plt.savefig(loss_plot_path, dpi=300, bbox_inches='tight')
    plt.close()  # Close figure to prevent overlap

    # Plot and save accuracy separately
    plt.figure(figsize=(8, 5))
    plt.plot(train_accs, label='Train Acc')
    plt.plot(val_accs, label='Val Acc')
    plt.title('Model Accuracy')
    plt.xlabel('Epoch')
    plt.ylabel('Accuracy (%)')
    plt.legend()
    plt.savefig(accuracy_plot_path, dpi=300, bbox_inches='tight')
    plt.close()  # Close figure to prevent overlap

    # Show both plots
    plt.show()

    print(f"Loss plot saved at: {loss_plot_path}")
    print(f"Accuracy plot saved at: {accuracy_plot_path}")

def count_parameters(model):
    """Count trainable and total parameters of the model"""
    trainable_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
    total_params = sum(p.numel() for p in model.parameters())

    print(f"Trainable parameters: {trainable_params:,}")
    print(f"Non-trainable parameters: {total_params - trainable_params:,}")
    print(f"Total parameters: {total_params:,}")
def efficient_face():
    model = EfficientFace([4, 8, 4], [29, 116, 232, 464, 1024]).to('cuda')
    return model

def main():

    # Create model
    print("\nCreating model...")
    model_cla = efficient_face()
    print("\Loading pre-training model...")
    model_cla.fc = nn.Linear(1024, 12666)
    model_cla = torch.nn.DataParallel(model_cla).cuda()
    checkpoint = torch.load('./model/Pretrained_EfficientFace.tar')
    pre_trained_dict = checkpoint['state_dict']
    model_cla.load_state_dict(pre_trained_dict)
    model_cla.module.fc = nn.Linear(1024, 7).cuda()
    print("Loading Success")
    count_parameters(model_cla)
    # Train model
    print("\nTraining model...")
    model = train_model(
        model_cla,
        train_loader,
        val_loader,
        DEVICE,
        NUM_EPOCHS,
        MODEL_SAVE_PATH
    )
    
    # Sau khi train xong và lưu model, cập nhật metadata và trigger CI/CD
    print("\nUpdating model metadata and triggering CI/CD...")
    model_manager = HybridModelManager()
    model_manager.handle_model_update(
        MODEL_SAVE_PATH, 
        description="Model trained with new data, improved accuracy by 2%"
    )

if __name__ == "__main__":
    main()