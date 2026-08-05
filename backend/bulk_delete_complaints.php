<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $ids = $_POST['complaint_ids'] ?? ''; // Expecting comma-separated IDs

    if (!empty($ids)) {
        $idArray = explode(',', $ids);
        // Create placeholders (?, ?, ?)
        $placeholders = str_repeat('?,', count($idArray) - 1) . '?';

        try {
            // Soft delete for bulk (hide from resident)
            $query = "UPDATE complaints SET deleted_by_resident = 1 WHERE complaint_id IN ($placeholders)";
            $stmt = $conn->prepare($query);
            $stmt->execute($idArray);

            echo json_encode(["success" => true, "message" => count($idArray) . " complaints deleted successfully"]);
        } catch (PDOException $e) {
            echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "No complaints selected"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>
