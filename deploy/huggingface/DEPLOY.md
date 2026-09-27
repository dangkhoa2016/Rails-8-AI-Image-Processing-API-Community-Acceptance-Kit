# Hugging Face Static Space deployment

Generate the acceptance reports and static site first.

Then export a Space-ready directory:

```bash
ruby scripts/export_huggingface_space.rb \
  --site site \
  --out dist/huggingface-space
```

The exported directory contains:

- `README.md` with `sdk: static`;
- `app_file: index.html`;
- the landing page;
- the full report;
- the compact report;
- the gallery;
- metadata and SHA-256 checksums.

Push the contents of `dist/huggingface-space/` to the root of a Hugging Face
Space repository.

The Space is static only. It does not execute BiRefNet or MobileSAM inference and
does not require GPU/CPU inference hardware.
