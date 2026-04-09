const ftp = require('basic-ftp');
const { Readable } = require('stream');
const path = require('path');
const crypto = require('crypto');

module.exports = async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { fileName, fileData, folder } = req.body;
    if (!fileName || !fileData) return res.status(400).json({ error: 'fileName and fileData required' });

    // fileData is base64 data URL — strip the prefix
    const base64Match = fileData.match(/^data:[^;]+;base64,(.+)$/);
    const buffer = Buffer.from(base64Match ? base64Match[1] : fileData, 'base64');

    // Generate unique filename to avoid collisions
    const ext = path.extname(fileName);
    const baseName = path.basename(fileName, ext).replace(/[^a-zA-Z0-9_-]/g, '_');
    const uniqueName = `${baseName}_${crypto.randomBytes(4).toString('hex')}${ext}`;

    // Target folder on FTP
    const ftpFolder = folder ? `/uploads/${folder}` : '/uploads';
    const remotePath = `${ftpFolder}/${uniqueName}`;

    const client = new ftp.Client();
    client.ftp.verbose = false;

    await client.access({
      host: process.env.FTP_HOST,
      port: parseInt(process.env.FTP_PORT || '21'),
      user: process.env.FTP_USER,
      password: process.env.FTP_PASS,
      secure: false,
    });

    // Ensure directory exists
    await client.ensureDir(ftpFolder);

    // Upload from buffer
    const stream = Readable.from(buffer);
    await client.uploadFrom(stream, remotePath);
    client.close();

    // Build the public URL
    const publicBase = process.env.FTP_PUBLIC_URL || `https://in-detail.co.za`;
    const publicUrl = `${publicBase}${remotePath}`;

    return res.status(200).json({ url: publicUrl, fileName: uniqueName, originalName: fileName });
  } catch (err) {
    console.error('FTP upload error:', err);
    return res.status(500).json({ error: 'Upload failed: ' + err.message });
  }
};
