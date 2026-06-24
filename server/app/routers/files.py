import json
import os
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.file import (
    ClearResponse,
    DeleteRequest,
    DeleteResponse,
    SyncRequest,
    SyncResponse,
)
from app.services import file_service, s3_service

router = APIRouter(prefix="/api/files", tags=["files"])


@router.get("")
async def list_files(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    records = await file_service.get_user_files(db, user.id)
    return {"files": [_file_to_dict(r) for r in records]}


@router.post("/sync", response_model=SyncResponse)
async def sync_file(
    req: SyncRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    data = req.model_dump(exclude_none=True)
    # Generate UUID if Flutter didn't provide one
    if "id" not in data or not data["id"]:
        data["id"] = uuid.uuid4().hex
    record = await file_service.create_file(db, user.id, data)
    return SyncResponse(success=True, id=record.id)


@router.post("/upload")
async def upload_file(
    file: UploadFile = File(...),
    file_id: str = Form(...),
    name: str = Form(...),
    file_type: str = Form(alias="type"),
    mime_type: str | None = Form(None, alias="mimeType"),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Receive file from phone, upload to S3, update existing DB record with s3Key."""
    # Save uploaded file to temp
    suffix = os.path.splitext(name)[1] or ".tmp"
    tmp_path = f"/tmp/idea_king_{uuid.uuid4().hex}{suffix}"
    content = await file.read()
    with open(tmp_path, "wb") as f:
        f.write(content)
    file_size = len(content)

    # Upload to S3
    s3_key = s3_service.generate_s3_key(name)
    uploaded = s3_service.upload_file(tmp_path, s3_key)

    # Clean up temp
    try:
        os.remove(tmp_path)
    except OSError:
        pass

    if not uploaded:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="S3 upload failed",
        )

    # Update existing DB record with s3Key
    from sqlalchemy import update as sa_update
    from app.models.file_record import FileRecord
    stmt = (
        sa_update(FileRecord)
        .where(FileRecord.id == file_id, FileRecord.user_id == user.id)
        .values(s3Key=s3_key, fileSize=file_size, mimeType=mime_type or file.content_type)
    )
    await db.execute(stmt)

    return {
        "success": True,
        "id": file_id,
        "s3Key": s3_key,
        "fileSize": file_size,
    }


@router.get("/{file_id}/download")
async def download_file(
    file_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Download a file from S3 through the API."""
    # Verify ownership
    records = await file_service.get_user_files(db, user.id)
    record = next((r for r in records if r.id == file_id), None)
    if not record or not record.s3Key:
        raise HTTPException(status_code=404, detail="File not found")

    tmp_path = s3_service.download_file(record.s3Key)
    if not tmp_path:
        raise HTTPException(status_code=502, detail="S3 download failed")

    media_type = record.mimeType or "application/octet-stream"
    return FileResponse(tmp_path, media_type=media_type, filename=record.name)


@router.post("/delete", response_model=DeleteResponse)
async def delete_file(
    req: DeleteRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    deleted = await file_service.delete_user_file(db, req.id, user.id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found or not yours",
        )
    return DeleteResponse(success=True)


@router.post("/clear", response_model=ClearResponse)
async def clear_files(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    count = await file_service.clear_user_files(db, user.id)
    return ClearResponse(success=True, deleted_count=count)


def _file_to_dict(r) -> dict:
    """Match the Flutter SharedFile.toJson() field naming."""
    d = {
        "id": r.id,
        "user_id": r.user_id,
        "name": r.name,
        "type": r.type,
        "localPath": r.localPath,
        "textContent": r.textContent,
        "sourceUri": r.sourceUri,
        "mimeType": r.mimeType,
        "fileSize": r.fileSize,
        "s3Key": r.s3Key,
        "uploadProgress": r.uploadProgress,
        "uploadError": r.uploadError,
        "uploadId": r.uploadId,
        "uploadedParts": r.uploadedParts,
        "tags": json.loads(r.tags) if r.tags else [],
        "description": r.description,
    }
    if r.receivedAt:
        if isinstance(r.receivedAt, str):
            d["receivedAt"] = r.receivedAt
        else:
            d["receivedAt"] = r.receivedAt.isoformat()
    return d
