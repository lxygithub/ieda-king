from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.file import (
    ClearResponse,
    DeleteRequest,
    DeleteResponse,
    FileResponse,
    SyncRequest,
    SyncResponse,
)
from app.services import file_service

router = APIRouter(prefix="/api/files", tags=["files"])


@router.get("")
async def list_files(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    records = await file_service.get_user_files(db, user.id)
    return {
        "files": [
            _file_to_dict(r) for r in records
        ]
    }


@router.post("/sync", response_model=SyncResponse)
async def sync_file(
    req: SyncRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    data = req.model_dump(exclude_none=True, exclude={"id"})
    record = await file_service.create_file(db, user.id, data)
    return SyncResponse(success=True, id=record.id)


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
    return ClearResponse(
        success=True, deleted_count=count
    )


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
        "tags": r.tags,
        "description": r.description,
    }
    if r.receivedAt:
        d["receivedAt"] = r.receivedAt.isoformat()
    return d
