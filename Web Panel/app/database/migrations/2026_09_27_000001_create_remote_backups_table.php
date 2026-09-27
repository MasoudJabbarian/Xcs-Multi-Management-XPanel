<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('remote_backups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('server_id')->constrained('servers')->cascadeOnDelete();
            $table->string('filename');
            $table->string('path');
            $table->dateTime('taken_at');
            $table->unsignedBigInteger('size')->default(0);
            $table->string('status')->default('success');
            $table->text('error')->nullable();
            $table->timestamps();

            $table->index(['server_id', 'taken_at']);
            $table->unique(['server_id', 'filename']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('remote_backups');
    }
};
