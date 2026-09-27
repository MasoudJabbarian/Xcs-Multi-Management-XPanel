<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class RemoteBackup extends Model
{
    use HasFactory;

    protected $fillable = [
        'server_id',
        'filename',
        'path',
        'taken_at',
        'size',
        'status',
        'error',
    ];

    protected $casts = [
        'taken_at' => 'datetime',
        'size' => 'integer',
    ];

    public function server()
    {
        return $this->belongsTo(Servers::class, 'server_id');
    }
}
