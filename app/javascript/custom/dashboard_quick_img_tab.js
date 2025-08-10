document.addEventListener('turbo:load', () => {
  const tabButton = document.getElementById('quickImgTabButton');
  const panel = document.getElementById('quickImgPanel');
  const dropZone = document.getElementById('quickImgDropZone');
  const imgList = document.getElementById('quickImgList');
  const deleteButton = document.getElementById('deleteSelectedImgsButton');

  if (!tabButton || !panel || !dropZone || !imgList || !deleteButton) {
    return; // Exit if essential elements aren't on the page
  }

  const STORAGE_KEY = 'quickDashboardImages';

  // Load images from localStorage and add to DOM (including 'type')
  function loadImages() {
    imgList.innerHTML = ''; 
    const images = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
    images.forEach(imgData => addImageToDOM(imgData.url, imgData.id, imgData.type));
  }

  // Save images array to localStorage
  function saveImages(images) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(images));
  }

  // Add single image entry to DOM, with optional type parameter
  function addImageToDOM(imageUrl, imageId, type = 'url') {
    const itemDiv = document.createElement('div');
    itemDiv.classList.add('quick-img-item');
    itemDiv.dataset.id = imageId;

    // Add a class based on type for possible styling differentiation
    itemDiv.classList.add(`quick-img-type-${type}`);

    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.classList.add('form-check-input'); // Bootstrap styling
    itemDiv.appendChild(checkbox);

    const previewContainer = document.createElement('a');
    previewContainer.href = imageUrl;
    previewContainer.target = '_blank';
    previewContainer.classList.add('img-preview-container');

    const imgElement = document.createElement('img');
    imgElement.src = imageUrl;
    imgElement.alt = 'Quick Ref';
    previewContainer.appendChild(imgElement);
    itemDiv.appendChild(previewContainer);

    const urlText = document.createElement('a');
    urlText.href = imageUrl;
    urlText.target = '_blank';
    urlText.textContent = imageUrl.length > 30 ? imageUrl.substring(0, 27) + '...' : imageUrl;
    urlText.classList.add('img-url-link');
    urlText.title = imageUrl; // Tooltip shows full URL
    itemDiv.appendChild(urlText);

    imgList.appendChild(itemDiv);
  }

  // Toggle the visibility of the image panel
  tabButton.addEventListener('click', () => {
    panel.classList.toggle('open');
  });

  // Handle adding/removing a loading message in dropZone
  function showLoading(message) {
    let loadingDiv = dropZone.querySelector('.loading-message');
    if (!loadingDiv) {
      loadingDiv = document.createElement('div');
      loadingDiv.className = 'loading-message';
      loadingDiv.style.position = 'absolute';
      loadingDiv.style.top = '50%';
      loadingDiv.style.left = '50%';
      loadingDiv.style.transform = 'translate(-50%, -50%)';
      loadingDiv.style.padding = '10px 20px';
      loadingDiv.style.backgroundColor = 'rgba(0,0,0,0.7)';
      loadingDiv.style.color = 'white';
      loadingDiv.style.borderRadius = '4px';
      dropZone.style.position = 'relative'; // Ensure positioning context
      dropZone.appendChild(loadingDiv);
    }
    loadingDiv.textContent = message;
    loadingDiv.style.display = 'block';
  }

  function hideLoading() {
    const loadingDiv = dropZone.querySelector('.loading-message');
    if (loadingDiv) {
      loadingDiv.style.display = 'none';
    }
  }

  // Drag and Drop event handlers
  dropZone.addEventListener('dragover', event => {
    event.preventDefault(); // Allow drop
    dropZone.classList.add('drag-over');
  });

  dropZone.addEventListener('dragenter', event => {
    event.preventDefault();
    dropZone.classList.add('drag-over');
  });

  dropZone.addEventListener('dragleave', () => {
    dropZone.classList.remove('drag-over');
  });

  dropZone.addEventListener('drop', async event => {
    event.preventDefault();
    dropZone.classList.remove('drag-over');

    // Check for local files first
    if (event.dataTransfer.files && event.dataTransfer.files.length > 0) {
      const files = Array.from(event.dataTransfer.files);
      const imageFiles = files.filter(file => file.type.startsWith('image/'));

      if (imageFiles.length === 0) {
        alert('Please drop image files only.');
        return;
      }

      showLoading('Uploading images...');

      // We will upload files sequentially to keep things simple
      for (const file of imageFiles) {
        try {
          const formData = new FormData();
          formData.append('quick_image_upload[image]', file);

          // Get Rails CSRF token from meta tag
          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");

          console.log('Uploading file:', file.name);

          const response = await fetch('/dashboard/upload_quick_image', {
            method: 'POST',
            headers: {
              'X-CSRF-Token': csrfToken
              // Content-Type set automatically for FormData
            },
            body: formData
          });

          if (!response.ok) {
            let errorText = `Server error: ${response.statusText}`;
            try {
              const errData = await response.json();
              errorText = errData.message || JSON.stringify(errData);
            } catch {
              // fallback error text
            }
            throw new Error(errorText);
          }

          const data = await response.json();

          if (data.image_url && data.image_id) {
            console.log('File uploaded successfully:', data.image_url);
            const images = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
            images.push({ url: data.image_url, id: data.image_id, type: 'uploaded' });
            saveImages(images);
            addImageToDOM(data.image_url, data.image_id, 'uploaded');
          } else {
            console.error('Upload response missing image_url or image_id.', data);
            alert('Upload response missing image_url or image_id.');
          }

        } catch (error) {
          console.error('Error uploading file:', error);
          alert(`Error uploading file: ${error.message || 'Unknown error'}`);
        }
      }

      hideLoading();

    } else {
      // Fallback to existing URL extraction logic
      let imageUrl = null;

      if (event.dataTransfer.types.includes('text/html')) {
        const htmlData = event.dataTransfer.getData('text/html');
        const doc = new DOMParser().parseFromString(htmlData, 'text/html');
        const img = doc.querySelector('img');
        if (img && img.src) {
          imageUrl = img.src;
        }
      }

      if (!imageUrl && event.dataTransfer.types.includes('text/uri-list')) {
        imageUrl = event.dataTransfer.getData('text/uri-list');
      } else if (!imageUrl && event.dataTransfer.types.includes('text/plain')) {
        const textData = event.dataTransfer.getData('text/plain');
        if (textData.match(/\.(jpeg|jpg|gif|png|svg|webp)(\?.*)?$/i) && textData.startsWith('http')) {
          imageUrl = textData;
        }
      }

      if (imageUrl) {
        const images = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
        const imageId = 'img-' + Date.now();
        images.push({ url: imageUrl, id: imageId, type: 'url' });
        saveImages(images);
        addImageToDOM(imageUrl, imageId, 'url');
        console.log('Image URL dropped and saved:', imageUrl);
      } else {
        console.warn('Could not extract image data from dropped item.');
      }
    }
  });

  // Handle selected image deletion
  deleteButton.addEventListener('click', () => {
    let images = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
    const itemsToRemove = [];

    imgList.querySelectorAll('.quick-img-item').forEach(item => {
      const checkbox = item.querySelector('input[type="checkbox"]');
      if (checkbox && checkbox.checked) {
        itemsToRemove.push(item.dataset.id);
        item.remove();
      }
    });

    if (itemsToRemove.length > 0) {
      images = images.filter(img => !itemsToRemove.includes(img.id));
      saveImages(images);
    }
  });

  // Initial load on page load
  loadImages();
});
